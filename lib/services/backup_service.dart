import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/backup_history_dao.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Result of a backup export operation.
enum BackupExportResult {
  success,
  canceled,
  failed,
}

/// Result of a backup import/restore operation.
enum BackupImportResult {
  success,
  canceled,
  invalidFile,
  incompatible,
  failed,
}

/// Result of a backup location selection operation.
enum BackupLocationResult {
  selected,
  canceled,
  failed,
}

/// Backup & Restore service.
///
/// Architecture: UI → Provider → BackupService → DAO → SQLite
///
/// All methods enforce the `backup_restore` permission (Admin only).
/// The service handles:
/// - Backup location selection, persistence, and validation
/// - Export (create backup to the saved destination)
/// - Import (restore from user-selected file with validation)
/// - Backup history CRUD
/// - Safety backup before destructive restore
/// - Activity logging
/// - Notifications
class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SessionManager _sessionManager = SessionManager();
  final BackupHistoryDao _backupHistoryDao = BackupHistoryDao();
  final ActivityLogService _activityLogService = ActivityLogService();
  final NotificationService _notificationService = NotificationService();

  /// SharedPreferences key for the persisted backup destination directory.
  static const _backupLocationKey = 'backup_location';

  /// Required Pinoy POS tables that must exist in a valid backup file.
  static const _requiredTables = [
    'users',
    'categories',
    'products',
    'sales',
    'sale_items',
    'stock_history',
    'activity_logs',
    'notifications',
    'announcements',
    'settings',
    'ai_usage',
    'trash',
    'backup_history',
    'export_history',
    'backup_metadata',
  ];

  // ── Backup Location Management ──────────────────────────────────────

  /// Returns the saved backup destination directory path, or null if no
  /// location has been configured by the Admin.
  Future<String?> getSavedBackupLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backupLocationKey);
  }

  /// Persists the chosen backup destination directory path.
  Future<void> _setBackupLocation(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupLocationKey, path);
  }

  /// Clears the saved backup destination.
  Future<void> clearBackupLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backupLocationKey);
  }

  /// Validates that the saved backup location is still accessible:
  /// the directory exists and the app can write to it.
  Future<bool> isLocationValid(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      // Verify writability by creating and removing a tiny temp file.
      final probe = File(p.join(path, '.pinoy_pos_probe'));
      await probe.writeAsString('probe', flush: true);
      await probe.delete();
      return true;
    } catch (e) {
      _log('Backup location validation failed for "$path": $e');
      return false;
    }
  }

  /// Opens the platform directory picker so the Admin can choose where
  /// future backups will be saved.
  ///
  /// Returns a [BackupLocationResult] record. On success, [path] holds the
  /// chosen directory and it is persisted for future backups.
  Future<({BackupLocationResult result, String? path, String? error})>
      pickBackupLocation() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    String? selectedPath;
    try {
      selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose Backup Location',
      );
    } catch (e) {
      _log('Directory picker failed: $e');
      return (
        result: BackupLocationResult.failed,
        path: null,
        error: 'The location picker could not be opened. $e',
      );
    }

    if (selectedPath == null || selectedPath.isEmpty) {
      return (
        result: BackupLocationResult.canceled,
        path: null,
        error: null,
      );
    }

    // Validate the chosen directory is usable before persisting.
    if (!await isLocationValid(selectedPath)) {
      return (
        result: BackupLocationResult.failed,
        path: null,
        error: 'The selected location cannot be written to. '
            'Please choose a different folder.',
      );
    }

    await _setBackupLocation(selectedPath);

    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_LOCATION_SET',
        entity: 'backup',
        details: 'Backup location set to: $selectedPath',
      );
    } catch (e) {
      _log('Failed to log backup location change: $e');
    }

    return (
      result: BackupLocationResult.selected,
      path: selectedPath,
      error: null,
    );
  }

  /// Returns a short, user-readable label for a saved backup location
  /// (the last 2-3 path segments), suitable for display in the status card.
  String getDisplayLocation(String path) {
    final parts = p.split(path);
    if (parts.isEmpty) return path;
    if (parts.length <= 3) return parts.join(' › ');
    return '... › ${parts.sublist(parts.length - 3).join(' › ')}';
  }

  // ── Export / Create Backup ───────────────────────────────────────────

  /// Creates a backup and saves it to the configured destination.
  ///
  /// When [destinationDirectory] is provided, the backup is written
  /// directly to that directory using an auto-generated filename. This is
  /// the normal flow once the Admin has chosen a backup location.
  ///
  /// When [destinationDirectory] is null, the platform save-file dialog
  /// is used as a fallback (primarily for desktop platforms).
  ///
  /// If [onConfirm] is provided, it is called after the destination is
  /// resolved but before the backup is written. If it returns false, the
  /// export is canceled and the temp file is cleaned up.
  ///
  /// Returns [BackupExportResult.success] with the saved path, or
  /// [BackupExportResult.canceled] / [BackupExportResult.failed] (with an
  /// [error] message on failure).
  Future<({
    BackupExportResult result,
    String? path,
    String? displayName,
    String? error,
  })> exportBackup({
    String? destinationDirectory,
    Future<bool> Function(String selectedPath, String displayName)? onConfirm,
  }) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    // 1. Create the backup in a temporary location first.
    final db = await _dbHelper.database;
    final dbPath = db.path;
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final tempBackupPath =
        p.join(tempDir.path, 'pinoy_pos_backup_$timestamp.db');

    try {
      await File(dbPath).copy(tempBackupPath);
    } catch (e) {
      _log('Failed to copy database to temp file: $e');
      return (
        result: BackupExportResult.failed,
        path: null,
        displayName: null,
        error: 'Could not read the local database. $e',
      );
    }

    // Write backup metadata into the temp copy so import can verify
    // this is a genuine Pinoy POS backup.
    await _writeBackupMetadata(tempBackupPath);

    // Validate the temp backup is non-empty.
    final tempFile = File(tempBackupPath);
    final tempStat = await tempFile.stat();
    if (tempStat.size == 0) {
      await _safeDelete(tempFile);
      return (
        result: BackupExportResult.failed,
        path: null,
        displayName: null,
        error: 'The backup file was empty. Please try again.',
      );
    }

    // 2. Resolve the destination path.
    final defaultName = 'pinoy_pos_backup_$timestamp.db';
    String savedPath;
    String displayName;

    if (destinationDirectory != null) {
      // Location-based export: write directly to the saved directory.
      savedPath = p.join(destinationDirectory, defaultName);
      displayName = defaultName;
    } else {
      // Fallback: ask the user for a save destination via the save dialog.
      String? pickedPath;
      try {
        pickedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Backup',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: ['db'],
        );
      } catch (e) {
        _log('Save file picker failed: $e');
        await _safeDelete(tempFile);
        return (
          result: BackupExportResult.failed,
          path: null,
          displayName: null,
          error: 'The save dialog could not be opened. $e',
        );
      }

      if (pickedPath == null || pickedPath.isEmpty) {
        await _safeDelete(tempFile);
        return (
          result: BackupExportResult.canceled,
          path: null,
          displayName: null,
          error: null,
        );
      }

      savedPath = pickedPath;
      displayName = p.basename(savedPath);
    }

    // Show confirmation dialog if callback is provided.
    if (onConfirm != null) {
      final confirmed = await onConfirm(savedPath, displayName);
      if (!confirmed) {
        await _safeDelete(tempFile);
        return (
          result: BackupExportResult.canceled,
          path: null,
          displayName: null,
          error: null,
        );
      }
    }

    // 3. Copy temp backup to the chosen destination.
    try {
      await tempFile.copy(savedPath);
    } catch (e) {
      _log('Failed to copy backup to destination "$savedPath": $e');
      await _safeDelete(tempFile);
      return (
        result: BackupExportResult.failed,
        path: null,
        displayName: null,
        error: destinationDirectory != null
            ? 'Could not write to the backup location. The folder may no '
                'longer be accessible. $e'
            : 'Could not save the backup to the chosen destination. $e',
      );
    }

    // Clean up temp file.
    await _safeDelete(tempFile);

    // 4. Verify the saved file.
    final savedFile = File(savedPath);
    final savedStat = await savedFile.stat();
    if (savedStat.size == 0) {
      return (
        result: BackupExportResult.failed,
        path: null,
        displayName: null,
        error: 'The saved backup file is empty. Please try again.',
      );
    }

    // 5. Record in backup_history.
    await _backupHistoryDao.insert(BackupHistory(
      filePath: savedPath,
      fileSize: savedStat.size,
      createdBy: _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    ));

    // 6. Log activity.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_CREATED',
        entity: 'backup',
        details:
            'Backup exported to: $displayName (${_formatFileSize(savedStat.size)})',
      );
    } catch (e) {
      _log('Failed to log backup creation: $e');
    }

    // 7. Notification.
    try {
      await _notificationService.createNotification(
        title: 'Backup Created',
        message:
            'Your Pinoy POS backup ($displayName) was saved successfully.',
        type: 'backup',
      );
    } catch (e) {
      _log('Failed to create backup notification: $e');
    }

    return (
      result: BackupExportResult.success,
      path: savedPath,
      displayName: displayName,
      error: null,
    );
  }

  // ── Import / Restore Backup ──────────────────────────────────────────

  /// Opens a file picker for the user to select a backup file, validates it,
  /// and restores it after confirmation.
  ///
  /// Returns [BackupImportResult.success] on successful restore.
  Future<({BackupImportResult result, String? displayName, int? fileSize})>
      importBackup() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    // 1. Open file picker.
    FilePickerResult? pickerResult;
    try {
      pickerResult = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Backup',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
    } catch (e) {
      _log('File picker failed: $e');
      // Fallback: try any file type.
      try {
        pickerResult = await FilePicker.platform.pickFiles(
          dialogTitle: 'Import Backup',
        );
      } catch (e2) {
        _log('File picker fallback also failed: $e2');
        return (
          result: BackupImportResult.failed,
          displayName: null,
          fileSize: null,
        );
      }
    }

    if (pickerResult == null || pickerResult.files.isEmpty) {
      return (
        result: BackupImportResult.canceled,
        displayName: null,
        fileSize: null,
      );
    }

    final pickedFile = pickerResult.files.first;
    final selectedPath = pickedFile.path;
    final displayName = pickedFile.name;

    if (selectedPath == null) {
      // Web or platform where path is unavailable.
      return (
        result: BackupImportResult.invalidFile,
        displayName: displayName,
        fileSize: null,
      );
    }

    // 2. Validate the selected file.
    final validationResult = await _validateBackupFile(selectedPath);
    if (validationResult != BackupImportResult.success) {
      try {
        await _activityLogService.logActivity(
          action: 'BACKUP_RESTORE_FAILED',
          entity: 'backup',
          details: 'Import validation failed for: $displayName',
        );
      } catch (e) {
        _log('Failed to log import validation failure: $e');
      }

      return (
        result: validationResult,
        displayName: displayName,
        fileSize: null,
      );
    }

    final fileSize = await File(selectedPath).length();

    // 3. Create safety backup before destructive restore.
    final safetyPath = await _createSafetyBackup();

    // 4. Log restore started.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORE_STARTED',
        entity: 'backup',
        details:
            'Restoring from: $displayName (${_formatFileSize(fileSize)})',
      );
    } catch (e) {
      _log('Failed to log restore start: $e');
    }

    // 5. Perform the restore.
    final success = await _performRestore(selectedPath);

    if (!success) {
      // Restore failed — attempt to recover from safety backup.
      if (safetyPath != null) {
        await _performRestore(safetyPath);
      }

      try {
        await _activityLogService.logActivity(
          action: 'BACKUP_RESTORE_FAILED',
          entity: 'backup',
          details: 'Restore failed for: $displayName',
        );
      } catch (e) {
        _log('Failed to log restore failure: $e');
      }

      // Clean up safety backup.
      if (safetyPath != null) {
        await _safeDelete(File(safetyPath));
      }

      return (
        result: BackupImportResult.failed,
        displayName: displayName,
        fileSize: fileSize,
      );
    }

    // 6. Log success.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORED',
        entity: 'backup',
        details: 'Successfully restored from: $displayName',
      );
    } catch (e) {
      _log('Failed to log restore success: $e');
    }

    // 7. Notification.
    try {
      await _notificationService.createNotification(
        title: 'Backup Restored',
        message: 'Your Pinoy POS data has been restored successfully.',
        type: 'backup',
      );
    } catch (e) {
      _log('Failed to create restore notification: $e');
    }

    // 8. Clean up safety backup.
    if (safetyPath != null) {
      await _safeDelete(File(safetyPath));
    }

    return (
      result: BackupImportResult.success,
      displayName: displayName,
      fileSize: fileSize,
    );
  }

  // ── Restore from History Path ────────────────────────────────────────

  /// Restores a backup from a known file path (e.g. from backup history).
  ///
  /// Validates the file, creates a safety backup, performs the restore,
  /// and logs the action. This is used when restoring from history
  /// (where the file path is already known) rather than importing
  /// a new file via the picker.
  Future<BackupImportResult> restoreFromPath(String backupPath) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    // 1. Validate.
    final validationResult = await _validateBackupFile(backupPath);
    if (validationResult != BackupImportResult.success) {
      try {
        await _activityLogService.logActivity(
          action: 'BACKUP_RESTORE_FAILED',
          entity: 'backup',
          details: 'Restore validation failed for: ${p.basename(backupPath)}',
        );
      } catch (e) {
        _log('Failed to log restore validation failure: $e');
      }
      return validationResult;
    }

    // 2. Safety backup.
    final safetyPath = await _createSafetyBackup();

    // 3. Log started.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORE_STARTED',
        entity: 'backup',
        details: 'Restoring from: ${p.basename(backupPath)}',
      );
    } catch (e) {
      _log('Failed to log restore start: $e');
    }

    // 4. Perform restore.
    final success = await _performRestore(backupPath);

    if (!success) {
      if (safetyPath != null) {
        await _performRestore(safetyPath);
      }
      try {
        await _activityLogService.logActivity(
          action: 'BACKUP_RESTORE_FAILED',
          entity: 'backup',
          details: 'Restore failed for: ${p.basename(backupPath)}',
        );
      } catch (e) {
        _log('Failed to log restore failure: $e');
      }
      if (safetyPath != null) {
        await _safeDelete(File(safetyPath));
      }
      return BackupImportResult.failed;
    }

    // 5. Log success.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORED',
        entity: 'backup',
        details: 'Successfully restored from: ${p.basename(backupPath)}',
      );
    } catch (e) {
      _log('Failed to log restore success: $e');
    }

    // 6. Notification.
    try {
      await _notificationService.createNotification(
        title: 'Backup Restored',
        message: 'Your Pinoy POS data has been restored successfully.',
        type: 'backup',
      );
    } catch (e) {
      _log('Failed to create restore notification: $e');
    }

    // 7. Clean up safety backup.
    if (safetyPath != null) {
      await _safeDelete(File(safetyPath));
    }

    return BackupImportResult.success;
  }

  // ── Backup History ───────────────────────────────────────────────────

  Future<List<BackupHistory>> getBackupHistory() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }
    return await _backupHistoryDao.getAll();
  }

  Future<bool> deleteBackup(int id, String filePath) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Best-effort file cleanup — the history record is still removed.
      _log('Could not delete backup file "$filePath": $e');
    }
    await _backupHistoryDao.delete(id);
    return true;
  }

  /// Returns the most recent backup, or null if none exist.
  Future<BackupHistory?> getLatestBackup() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }
    final backups = await _backupHistoryDao.getAll();
    if (backups.isEmpty) return null;
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups.first;
  }

  // ── Validation ───────────────────────────────────────────────────────

  /// Validates that the file at [path] is a legitimate Pinoy POS backup.
  ///
  /// Checks:
  /// 1. File exists and is non-empty
  /// 2. File is a valid SQLite database (can be opened)
  /// 3. Contains required Pinoy POS tables
  Future<BackupImportResult> _validateBackupFile(String path) async {
    final file = File(path);

    // Check file exists.
    if (!await file.exists()) {
      return BackupImportResult.invalidFile;
    }

    // Check non-empty.
    final stat = await file.stat();
    if (stat.size == 0) {
      return BackupImportResult.invalidFile;
    }

    // Check SQLite header (first 16 bytes should contain "SQLite format 3").
    try {
      final raf = await file.open();
      final header = await raf.read(16);
      await raf.close();
      final headerStr = String.fromCharCodes(header);
      if (!headerStr.startsWith('SQLite format 3')) {
        return BackupImportResult.invalidFile;
      }
    } catch (e) {
      _log('Could not read backup file header "$path": $e');
      return BackupImportResult.invalidFile;
    }

    // Open as SQLite database and verify required tables.
    Database? testDb;
    try {
      testDb = await openDatabase(path, readOnly: true);
      final tables = await testDb.query(
        'sqlite_master',
        where: "type = 'table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      for (final required in _requiredTables) {
        if (!tableNames.contains(required)) {
          await testDb.close();
          return BackupImportResult.incompatible;
        }
      }

      // Verify backup_metadata row identifies this as a Pinoy POS backup.
      try {
        final metaRows = await testDb.query(
          'backup_metadata',
          where: 'id = 1',
          limit: 1,
        );
        if (metaRows.isEmpty) {
          await testDb.close();
          return BackupImportResult.incompatible;
        }
        final appName = metaRows.first['app_name'] as String?;
        if (appName != AppConstants.appName) {
          await testDb.close();
          return BackupImportResult.incompatible;
        }
      } catch (e) {
        _log('Backup metadata validation failed: $e');
        await testDb.close();
        return BackupImportResult.incompatible;
      }
    } catch (e) {
      _log('Could not open backup file as SQLite database: $e');
      await _safeClose(testDb);
      return BackupImportResult.invalidFile;
    } finally {
      await _safeClose(testDb);
    }

    return BackupImportResult.success;
  }

  // ── Safety Backup ────────────────────────────────────────────────────

  /// Creates a temporary safety backup of the current database before
  /// a destructive restore. Returns the path to the safety backup,
  /// or null if it could not be created.
  Future<String?> _createSafetyBackup() async {
    try {
      final db = await _dbHelper.database;
      final dbPath = db.path;
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final safetyPath =
          p.join(tempDir.path, 'pinoy_pos_safety_$timestamp.db');
      await File(dbPath).copy(safetyPath);
      await _writeBackupMetadata(safetyPath);
      return safetyPath;
    } catch (e) {
      _log('Could not create safety backup: $e');
      return null;
    }
  }

  // ── Restore Execution ────────────────────────────────────────────────

  /// Replaces the live database file with the backup at [backupPath].
  /// Closes the database handle first, copies the file, then the next
  /// access re-opens the restored data.
  Future<bool> _performRestore(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) return false;

    final db = await _dbHelper.database;
    final dbPath = db.path;

    await _dbHelper.close();

    try {
      await backupFile.copy(dbPath);
      return true;
    } catch (e) {
      _log('Restore copy failed from "$backupPath" to "$dbPath": $e');
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Writes a metadata row into the backup database file identifying it
  /// as a genuine Pinoy POS backup.  This is called after copying the
  /// live database to a temp file during export.
  Future<void> _writeBackupMetadata(String backupPath) async {
    Database? metaDb;
    try {
      metaDb = await openDatabase(backupPath);
      await metaDb.insert(
        'backup_metadata',
        {
          'id': 1,
          'app_name': AppConstants.appName,
          'app_version': AppConstants.appVersion,
          'database_version': AppConstants.databaseVersion,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Best-effort: old backups created before this feature won't have
      // the table, and that's fine — they'll fail validation on import.
      _log('Could not write backup metadata: $e');
    } finally {
      await _safeClose(metaDb);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Safely deletes a file, ignoring any errors.
  Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } catch (e) {
      _log('Could not delete temp file: $e');
    }
  }

  /// Safely closes a database, ignoring any errors.
  Future<void> _safeClose(Database? db) async {
    try {
      await db?.close();
    } catch (e) {
      _log('Could not close database: $e');
    }
  }

  /// Logs a debug message with the full exception. In debug/development
  /// mode this prints to the console so the actual failure is visible
  /// during development. In release builds it is a no-op so users never
  /// see raw stack traces.
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[BackupService] $message');
    }
  }

  /// Returns a user-readable display name for a backup file path.
  /// On platforms where the path is a raw filesystem path, returns
  /// the basename. On Android SAF URIs, returns the document name.
  String getDisplayName(String filePath) {
    return p.basename(filePath);
  }
}
