import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/core/constants.dart' as constants;
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/backup_history_dao.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/data/models/backup_location.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/backup_storage_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Result of a backup export operation.
enum BackupExportResult { success, canceled, failed }

/// Result of a backup import/restore operation.
enum BackupImportResult { success, canceled, invalidFile, incompatible, failed }

/// Result of a backup location selection operation.
enum BackupLocationResult { selected, canceled, failed }

/// Result returned by [BackupService.exportBackup].
class BackupExportRecord {
  final BackupExportResult result;
  final String? error;
  final String? storageReference;
  final String? displayName;
  final int? fileSize;
  final BackupLocation? writtenTo;

  const BackupExportRecord({
    required this.result,
    this.error,
    this.storageReference,
    this.displayName,
    this.fileSize,
    this.writtenTo,
  });
}

/// Result returned by [BackupService.importBackup].
class BackupImportRecord {
  final BackupImportResult result;
  final String? displayName;
  final int? fileSize;
  final String? error;

  const BackupImportRecord({
    required this.result,
    this.displayName,
    this.fileSize,
    this.error,
  });
}

/// Internal exception used to surface specific, user-facing backup errors.
class _BackupServiceException implements Exception {
  final String message;
  _BackupServiceException(this.message);

  @override
  String toString() => message;
}

/// Backup & Restore service.
///
/// Architecture: UI → Provider → BackupService → BackupStorageService →
/// platform storage
///
/// All methods enforce the `backup_restore` permission (Admin only).
/// The service delegates all file-system / storage-access work to
/// [BackupStorageService] so each platform (Android SAF, Windows paths,
/// Web download) is handled correctly.
class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SessionManager _sessionManager = SessionManager();
  final BackupHistoryDao _backupHistoryDao = BackupHistoryDao();
  final ActivityLogService _activityLogService = ActivityLogService();
  final NotificationService _notificationService = NotificationService();
  final BackupStorageService _storage = BackupStorageService();

  /// SharedPreferences key for the persisted backup destination.
  ///
  /// v2 stores a JSON-encoded [BackupLocation]; v1 stored a plain path.
  static const _backupLocationKey = 'backup_location_v2';
  static const _legacyBackupLocationKey = 'backup_location';

  /// Core tables that must exist in any Pinoy POS backup, including legacy
  /// v1/v2 .db files. The value lists acceptable aliases (e.g. the legacy
  /// `activity_log` table was renamed to `activity_logs` in v3).
  static const _coreTableAliases = {
    'users': ['users'],
    'categories': ['categories'],
    'products': ['products'],
    'sales': ['sales'],
    'sale_items': ['sale_items'],
    'stock_history': ['stock_history'],
    'notifications': ['notifications'],
    'settings': ['settings'],
    'activity_logs': ['activity_logs', 'activity_log'],
  };

  /// Tables that are expected only when the backup was created at the current
  /// schema version. Older backups are allowed to miss these because the
  /// database will run [onUpgrade] and create them after the restore.
  static const _currentVersionOnlyTables = [
    'announcements',
    'ai_usage',
    'ai_quota',
    'trash',
    'backup_history',
    'export_history',
    'backup_metadata',
    'attachments',
  ];

  // ── Backup Location Management ───────────────────────────────────────

  /// Returns the saved default backup destination, or null if none is set.
  Future<BackupLocation?> getSavedBackupLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_backupLocationKey);
    if (json != null && json.isNotEmpty) {
      final location = BackupLocation.fromJsonString(json);
      if (!location.isNone) return location;
    }

    // Migrate from the v1 plain-path key.
    final legacy = prefs.getString(_legacyBackupLocationKey);
    if (legacy != null && legacy.isNotEmpty) {
      final migrated = _migrateLegacyLocation(legacy);
      await _setBackupLocation(migrated);
      await prefs.remove(_legacyBackupLocationKey);
      if (!migrated.isNone) return migrated;
    }

    // Use a default writable desktop folder when nothing is configured.
    if (!kIsWeb) {
      final defaultLocation = await _storage.getDefaultDesktopLocation();
      if (defaultLocation != null && !defaultLocation.isNone) {
        await _setBackupLocation(defaultLocation);
        return defaultLocation;
      }
    }

    return null;
  }

  /// Persists the chosen default backup destination.
  Future<void> _setBackupLocation(BackupLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupLocationKey, location.toJsonString());
  }

  /// Clears the saved default backup destination.
  Future<void> clearBackupLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backupLocationKey);
    await prefs.remove(_legacyBackupLocationKey);
  }

  /// Verifies that the saved backup destination is still accessible.
  Future<bool> isLocationValid(BackupLocation location) async {
    return _storage.isLocationValid(location);
  }

  /// Returns a short, user-readable label for a saved backup location.
  String getDisplayLocation(BackupLocation? location) {
    if (location == null || location.isNone) return 'No folder selected';
    return _storage.getLocationDisplayName(location);
  }

  /// Returns a user-readable filename from a backup history record.
  Future<String> getDisplayName(BackupHistory backup) async {
    if (backup.displayName != null && backup.displayName!.isNotEmpty) {
      return backup.displayName!;
    }
    return _storage.getDisplayName(backup.filePath);
  }

  /// Returns a user-readable location for a backup history record.
  Future<String> getDisplayLocationForHistory(BackupHistory backup) async {
    if (backup.locationJson != null && backup.locationJson!.isNotEmpty) {
      try {
        final location = BackupLocation.fromJsonString(backup.locationJson!);
        if (!location.isNone) {
          return _storage.getLocationDisplayName(location);
        }
      } catch (e) {
        _log('Failed to parse locationJson for history: $e');
      }
    }
    if (_isContentUri(backup.filePath)) {
      return 'Selected folder';
    }

    final localPath = _toLocalPath(backup.filePath);
    if (localPath == null) return 'Selected folder';

    return _storage.getLocationDisplayName(
      BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: p.dirname(localPath),
        displayName: '',
      ),
    );
  }

  /// Opens the platform folder picker and, if the user selects a folder,
  /// either persists it as the default destination ([persist] = true) or
  /// returns it as a one-time override ([persist] = false).
  Future<({BackupLocationResult result, BackupLocation? location, String? error})>
      pickBackupLocation({
    BackupLocation? initial,
    bool persist = true,
  }) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    BackupLocation? picked;
    try {
      picked = await _storage.pickLocation(initial: initial);
    } on BackupStorageException catch (e) {
      _log('Directory picker failed: $e');
      return (
        result: BackupLocationResult.failed,
        location: null,
        error: e.message,
      );
    } catch (e) {
      _log('Directory picker failed: $e');
      return (
        result: BackupLocationResult.failed,
        location: null,
        error: 'The location picker could not be opened. $e',
      );
    }

    if (picked == null || picked.isNone) {
      return (
        result: BackupLocationResult.canceled,
        location: null,
        error: null,
      );
    }

    final valid = await _storage.isLocationValid(picked);
    if (!valid) {
      return (
        result: BackupLocationResult.failed,
        location: null,
        error: 'The selected location cannot be written to. '
            'Please choose a different folder.',
      );
    }

    if (persist) {
      await _setBackupLocation(picked);

      try {
        await _activityLogService.logActivity(
          action: 'BACKUP_LOCATION_SET',
          entity: 'backup',
          details: 'Backup location set to: ${picked.displayName}',
        );
      } catch (e) {
        _log('Failed to log backup location change: $e');
      }
    }

    return (
      result: BackupLocationResult.selected,
      location: picked,
      error: null,
    );
  }

  // ── Export / Create Backup ───────────────────────────────────────────

  /// Creates a backup and writes it to the configured destination.
  ///
  /// - [override]: when set, the backup is written to this one-time
  ///   location instead of the saved default.
  /// - [setAsDefault]: when true and [override] is provided, the override
  ///   location replaces the saved default after a successful export.
  Future<BackupExportRecord> exportBackup({
    BackupLocation? override,
    bool setAsDefault = false,
  }) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    // 1. Prepare the backup payload in a temporary file.
    final String tempPath;
    try {
      tempPath = await _prepareBackupFile();
    } on _BackupServiceException catch (e) {
      return BackupExportRecord(
        result: BackupExportResult.failed,
        error: e.message,
      );
    } catch (e) {
      _log('Unexpected error while preparing backup: $e');
      return BackupExportRecord(
        result: BackupExportResult.failed,
        error: 'Could not prepare the backup file: $e',
      );
    }

    try {
      final tempFile = File(tempPath);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        await _safeDelete(tempFile);
        return const BackupExportRecord(
          result: BackupExportResult.failed,
          error: 'The backup file was empty.',
        );
      }
    } catch (e) {
      _log('Failed to verify prepared backup file: $e');
      await _safeDelete(File(tempPath));
      return BackupExportRecord(
        result: BackupExportResult.failed,
        error: 'Could not verify the prepared backup: $e',
      );
    }

    // 2. Determine default filename and saved location.
    final defaultName = _generateBackupFileName();
    final savedLocation = await getSavedBackupLocation();
    final targetLocation = override ?? savedLocation;

    // 3. Write to the chosen storage.
    _log('Writing backup to target: $targetLocation');
    final write = await _storage.saveBackup(
      sourceFilePath: tempPath,
      defaultFileName: defaultName,
      location: targetLocation,
      defaultLocation: savedLocation,
    );

    await _safeDelete(File(tempPath));

    if (!write.success) {
      return BackupExportRecord(
        result: write.error == null
            ? BackupExportResult.canceled
            : BackupExportResult.failed,
        error: write.error,
      );
    }

    // 4. Update the default location if requested.
    if (setAsDefault && override != null && !override.isNone) {
      await _setBackupLocation(override);
    }

    // 5. Record in backup_history.
    await _backupHistoryDao.insert(BackupHistory(
      filePath: write.storageReference ?? '',
      displayName: write.displayName,
      storageType: write.writtenTo?.type.name,
      locationJson: write.writtenTo?.toJsonString(),
      fileSize: write.fileSize,
      createdBy: _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    ));

    // 6. Log activity.
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_CREATED',
        entity: 'backup',
        details:
            'Backup exported to: ${write.displayName} (${_formatFileSize(write.fileSize)})',
      );
    } catch (e) {
      _log('Failed to log backup creation: $e');
    }

    // 7. Notification.
    try {
      await _notificationService.createNotification(
        title: 'Backup Created',
        message:
            'Your Pinoy POS backup (${write.displayName}) was saved successfully.',
        type: 'backup',
      );
    } catch (e) {
      _log('Failed to create backup notification: $e');
    }

    return BackupExportRecord(
      result: BackupExportResult.success,
      storageReference: write.storageReference,
      displayName: write.displayName,
      fileSize: write.fileSize,
      writtenTo: write.writtenTo,
    );
  }

  // ── Import / Restore Backup ──────────────────────────────────────────

  /// Opens a file picker for the user to select a backup file, validates it,
  /// and restores it after confirmation.
  Future<BackupImportRecord> importBackup() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    final read = await _storage.pickBackupForRestore();
    if (!read.success) {
      return BackupImportRecord(
        result: read.error == null
            ? BackupImportResult.canceled
            : BackupImportResult.failed,
        displayName: read.displayName,
        fileSize: read.fileSize,
        error: read.error,
      );
    }

    final filePath = read.filePath;
    if (filePath == null || filePath.isEmpty) {
      return BackupImportRecord(
        result: BackupImportResult.failed,
        displayName: read.displayName,
        fileSize: read.fileSize,
        error: 'The selected backup file could not be read.',
      );
    }

    return await _restoreFromFile(
      filePath,
      read.displayName ?? 'backup.db',
      read.fileSize ?? 0,
    );
  }

  /// Restores a backup from a known storage reference (used by history).
  Future<BackupImportRecord> restoreFromHistory(BackupHistory backup) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    final storageType = _typeFromString(backup.storageType);

    if (storageType == BackupStorageType.webDownload) {
      return const BackupImportRecord(
        result: BackupImportResult.failed,
        error: 'Web-downloaded backups cannot be restored from history.',
      );
    }

    final read = await _storage.readBackup(backup.filePath);
    if (!read.success) {
      return BackupImportRecord(
        result: BackupImportResult.failed,
        displayName: backup.displayName,
        fileSize: backup.fileSize,
        error: read.error,
      );
    }

    final tempPath = read.filePath;
    if (tempPath == null || tempPath.isEmpty) {
      return BackupImportRecord(
        result: BackupImportResult.invalidFile,
        displayName: read.displayName,
        fileSize: read.fileSize,
      );
    }

    return _restoreFromFile(
      tempPath,
      read.displayName ?? backup.displayName ?? 'backup.db',
      read.fileSize ?? await File(tempPath).length(),
    );
  }

  // ── Backup History ───────────────────────────────────────────────────

  Future<List<BackupHistory>> getBackupHistory() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }
    return await _backupHistoryDao.getAll();
  }

  Future<bool> deleteBackup(BackupHistory backup) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    final storageType = _typeFromString(backup.storageType);
    if (storageType == BackupStorageType.androidSaf ||
        _isContentUri(backup.filePath)) {
      await _storage.deleteBackup(backup.filePath);
    } else if (storageType != BackupStorageType.webDownload) {
      final localPath = _toLocalPath(backup.filePath);
      if (localPath == null) {
        _log('Could not delete backup file "${backup.filePath}": not a valid path.');
        return false;
      }
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        _log('Could not delete backup file "$localPath": $e');
      }
    }

    await _backupHistoryDao.delete(backup.id!);
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

  /// Validates a backup file.
  ///
  /// The canonical native format is a plain SQLite `.db` file.
  /// Legacy zip backups (created by earlier versions of Pinoy POS) are still
  /// supported: the zip is extracted and the contained `.db` is validated.
  /// Returns `incompatible` or `invalidFile` for files that do not contain a
  /// valid Pinoy POS database.
  Future<BackupImportResult> _validateBackupFile(String path) async {
    final localPath = _toLocalPath(path);
    if (localPath == null) return BackupImportResult.invalidFile;
    final file = File(localPath);

    if (!await file.exists()) {
      return BackupImportResult.invalidFile;
    }

    final stat = await file.stat();
    if (stat.size == 0) {
      return BackupImportResult.invalidFile;
    }

    final isZip = await _isZipFile(localPath);

    String? dbPath;
    String? extractedDir;
    if (isZip) {
      extractedDir = await _extractBackupZip(localPath);
      if (extractedDir == null) {
        _log('Could not extract backup zip: $localPath');
        return BackupImportResult.invalidFile;
      }
      dbPath = await _findDbFileInDirectory(extractedDir);
      if (dbPath == null) {
        await _safeDeleteDir(Directory(extractedDir));
        return BackupImportResult.invalidFile;
      }
    } else {
      dbPath = localPath;
    }

    final result = await _validateDbFile(dbPath);

    if (extractedDir != null) {
      await _safeDeleteDir(Directory(extractedDir));
    }

    return result;
  }

  /// Returns `true` when [path] starts with the PK zip signature.
  Future<bool> _isZipFile(String path) async {
    try {
      final raf = await File(path).open();
      final header = await raf.read(4);
      await raf.close();
      return header.length >= 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          header[2] == 0x03 &&
          header[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  /// Extracts a backup zip to a temp directory and returns its path.
  Future<String?> _extractBackupZip(String zipPath) async {
    String? tempDir;
    try {
      tempDir = await _tempDir('pinoy_pos_import_${_timestamp()}');
      final input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeBuffer(input);
      await input.close();

      for (final file in archive) {
        // Archive entry names may use '/' or '\' depending on the creator.
        // Normalize to the platform separator and remove any traversal.
        final safeName = p.normalize(file.name.replaceAll('\\', '/'));
        final outPath = p.join(tempDir, safeName);
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          final content = file.content;
          if (content is List<int>) {
            await outFile.writeAsBytes(content);
          } else if (content is String) {
            await outFile.writeAsString(content);
          } else {
            _log('Unknown content type for archive file "${file.name}"');
          }
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      return tempDir;
    } catch (e) {
      _log('Zip extraction failed: $e');
      if (tempDir != null) await _safeDeleteDir(Directory(tempDir));
      return null;
    }
  }

  /// Finds the SQLite database file in an extracted backup directory.
  ///
  /// Prefers `pinoy_pos.db` if present, otherwise returns the first `.db` file.
  Future<String?> _findDbFileInDirectory(String dir) async {
    try {
      final root = Directory(dir);
      if (!await root.exists()) return null;

      final preferred = File(p.join(dir, 'pinoy_pos.db'));
      if (await preferred.exists()) return preferred.path;

      final files = await root.list(recursive: false).toList();
      for (final entity in files) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.db') {
          return entity.path;
        }
      }
    } catch (e) {
      _log('Could not find database in backup directory: $e');
    }
    return null;
  }

  /// Validates that [dbPath] is a valid Pinoy POS SQLite database.
  Future<BackupImportResult> _validateDbFile(String dbPath) async {
    try {
      final raf = await File(dbPath).open();
      final header = await raf.read(16);
      await raf.close();
      final headerStr = String.fromCharCodes(header);
      if (!headerStr.startsWith('SQLite format 3')) {
        return BackupImportResult.invalidFile;
      }
    } catch (e) {
      _log('Could not read backup file header "$dbPath": $e');
      return BackupImportResult.invalidFile;
    }

    Database? testDb;
    try {
      testDb = await openDatabase(dbPath, readOnly: true);
      final tables = await testDb.query(
        'sqlite_master',
        where: "type = 'table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      // Determine the schema version of the backup. Legacy .db files may be
      // many versions behind; opening them after restore will trigger
      // onUpgrade and create the missing tables automatically.
      int userVersion = 0;
      try {
        final versionRows = await testDb.rawQuery('PRAGMA user_version');
        if (versionRows.isNotEmpty) {
          final raw = versionRows.first.values.first;
          if (raw is int) {
            userVersion = raw;
          } else if (raw is String) {
            userVersion = int.tryParse(raw) ?? 0;
          }
        }
      } catch (e) {
        _log('Could not read PRAGMA user_version from backup: $e');
      }
      _log('Backup database user_version: $userVersion');

      // Core tables must be present in every supported backup (including
      // legacy v1/v2 .db files).  Accept the legacy `activity_log` name as
      // an alias for `activity_logs`.
      for (final entry in _coreTableAliases.entries) {
        final aliases = entry.value;
        final hasAnyAlias = aliases.any(tableNames.contains);
        if (!hasAnyAlias) {
          _log('Backup is missing core table(s): $aliases');
          await testDb.close();
          return BackupImportResult.incompatible;
        }
      }

      // For backups at the current schema version, also require the newer
      // tables.  Older backups are allowed to miss them because the database
      // will run onUpgrade after restore and create them.
      if (userVersion >= constants.AppConstants.databaseVersion) {
        final missing = <String>[];
        for (final required in _currentVersionOnlyTables) {
          if (!tableNames.contains(required)) {
            missing.add(required);
          }
        }
        if (missing.isNotEmpty) {
          _log('Backup at current version is missing table(s): $missing');
          await testDb.close();
          return BackupImportResult.incompatible;
        }
      } else {
        final missing = _currentVersionOnlyTables
            .where((t) => !tableNames.contains(t))
            .toList();
        if (missing.isNotEmpty) {
          _log('Legacy backup is missing newer tables (will be created by '
              'onUpgrade after restore): $missing');
        }
      }

      // Older backups may not have backup_metadata; allow them as long as
      // the required data tables were present.
      if (await _hasTable(testDb, 'backup_metadata')) {
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
          if (appName != constants.AppConstants.appName) {
            _log('Backup app_name mismatch: $appName');
            await testDb.close();
            return BackupImportResult.incompatible;
          }
        } catch (e) {
          _log('Backup metadata validation failed: $e');
          await testDb.close();
          return BackupImportResult.incompatible;
        }
      }

      // Run SQLite's built-in integrity check. A corrupted backup file
      // can pass the header and table-name checks but still have torn
      // pages or broken indexes.  Rejecting it here prevents restoring
      // a broken database over the user's current data.
      try {
        final integrityRows = await testDb.rawQuery(
          'PRAGMA integrity_check',
        );
        final integrityResult =
            integrityRows.isEmpty ? '' : integrityRows.first.values.first;
        if (integrityResult != 'ok') {
          _log('Backup integrity_check failed: $integrityResult');
          await testDb.close();
          return BackupImportResult.invalidFile;
        }
      } catch (e) {
        _log('Could not run integrity_check on backup: $e');
        await testDb.close();
        return BackupImportResult.invalidFile;
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

  // ── Restore internals ────────────────────────────────────────────────

  Future<BackupImportRecord> _restoreFromFile(
    String tempPath,
    String displayName,
    int fileSize,
  ) async {
    if (tempPath.isEmpty) {
      return const BackupImportRecord(
        result: BackupImportResult.failed,
        error: 'Could not create a temporary backup file.',
      );
    }

    final validation = await _validateBackupFile(tempPath);
    if (validation != BackupImportResult.success) {
      await _safeDelete(File(tempPath));
      return BackupImportRecord(
        result: validation,
        displayName: displayName,
        fileSize: fileSize,
      );
    }

    final safetyPath = await _createSafetyBackup();
    if (safetyPath == null || safetyPath.isEmpty) {
      _log('Safety backup could not be created; aborting restore.');
      await _safeDelete(File(tempPath));
      return BackupImportRecord(
        result: BackupImportResult.failed,
        error: 'A safety backup of the current database could not be created.',
        displayName: displayName,
        fileSize: fileSize,
      );
    }

    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORE_STARTED',
        entity: 'backup',
        details: 'Restoring from: $displayName (${_formatFileSize(fileSize)})',
      );
    } catch (e) {
      _log('Failed to log restore start: $e');
    }

    try {
      final (success, restoreError) = await _performRestore(tempPath);
      await _safeDelete(File(tempPath));

      if (!success) {
        // Restore failed: roll back to the safety backup before reporting.
        try {
          await _performRestore(safetyPath);
        } catch (e) {
          _log('Safety restore also failed: $e');
        }
        await _safeDelete(File(safetyPath));
        await _logRestoreFailure(displayName);
        return BackupImportRecord(
          result: BackupImportResult.failed,
          error: restoreError ?? 'The backup could not be restored.',
          displayName: displayName,
          fileSize: fileSize,
        );
      }

      await _logRestoreSuccess(displayName);
      await _safeDelete(File(safetyPath));
      return BackupImportRecord(
        result: BackupImportResult.success,
        displayName: displayName,
        fileSize: fileSize,
      );
    } catch (e) {
      _log('Backup restore failed: $e');
      // Roll back to the safety copy so the current database is not left
      // in a broken state.
      try {
        await _performRestore(safetyPath);
      } catch (e) {
        _log('Safety restore also failed: $e');
      }
      await _safeDelete(File(safetyPath));
      await _safeDelete(File(tempPath));
      await _logRestoreFailure(displayName);
      return BackupImportRecord(
        result: BackupImportResult.failed,
        error: 'Backup restore failed: $e',
        displayName: displayName,
        fileSize: fileSize,
      );
    }
  }

  Future<(bool, String?)> _performRestore(String backupPath) async {
    final isZip = await _isZipFile(backupPath);

    // For legacy zip backups, extract the database and attached files into a
    // temp directory first. Native .db backups are restored directly.
    String? sourceDbPath;
    String? evidenceSourceDir;
    String? qrSourceDir;
    String? imagesSourceDir;
    String? attachmentsSourceDir;
    String? extractedDir;

    if (isZip) {
      extractedDir = await _extractBackupZip(backupPath);
      if (extractedDir == null) {
        return (false, 'Could not extract the backup package.');
      }
      sourceDbPath = await _findDbFileInDirectory(extractedDir);
      if (sourceDbPath == null) {
        await _safeDeleteDir(Directory(extractedDir));
        return (false, 'The backup package does not contain a database file.');
      }
      final evidenceDir = Directory(p.join(extractedDir, 'payment_evidence'));
      if (await evidenceDir.exists()) {
        evidenceSourceDir = evidenceDir.path;
      }
      final qrDir = Directory(p.join(extractedDir, 'gcash_qr'));
      if (await qrDir.exists()) {
        qrSourceDir = qrDir.path;
      }
      final imagesDir = Directory(p.join(extractedDir, 'images'));
      if (await imagesDir.exists()) {
        imagesSourceDir = imagesDir.path;
      }
      final attachmentsDir = Directory(p.join(extractedDir, 'attachments'));
      if (await attachmentsDir.exists()) {
        attachmentsSourceDir = attachmentsDir.path;
      }
    } else {
      sourceDbPath = backupPath;
    }

    final dbPath = await _dbHelper.databasePath;
    final dbDir = p.dirname(dbPath);
    final dbName = p.basename(dbPath);
    _log('Restoring database from $sourceDbPath to $dbPath');

    // Close any open connection without trying to reopen the live database.
    // During restore the file at [dbPath] may be in a transient/corrupt state,
    // and [databasePath] gives us the path without opening it.
    await _dbHelper.closeIfOpen();

    // If the live database was running in WAL mode, the -wal and -shm files
    // in the application directory still belong to the old database.  Leaving
    // them behind and copying a new .db on top causes SQLite to apply the old
    // WAL to the new file, which can silently roll back the restored data.
    // Delete the old WAL/SHM/journal files before replacing the database.
    final walFile = File(p.join(dbDir, '$dbName-wal'));
    final shmFile = File(p.join(dbDir, '$dbName-shm'));
    final journalFile = File(p.join(dbDir, '$dbName-journal'));
    await _safeDelete(walFile);
    await _safeDelete(shmFile);
    await _safeDelete(journalFile);
    // Remove the current database file so the copy can create the new one.
    await _safeDelete(File(dbPath));

    try {
      await File(sourceDbPath).copy(dbPath);

      // Restore payment evidence, product images, and the GCash QR image if
      // the legacy zip backup contains them. Replace the current directories
      // so the database and files stay consistent.
      if (evidenceSourceDir != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final evidenceTarget = Directory(p.join(appDir.path, 'payment_evidence'));
        if (await evidenceTarget.exists()) {
          await evidenceTarget.delete(recursive: true);
        }
        await _copyDirectory(Directory(evidenceSourceDir), evidenceTarget);
      }

      if (qrSourceDir != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final qrTarget = Directory(p.join(appDir.path, 'gcash_qr'));
        if (await qrTarget.exists()) {
          await qrTarget.delete(recursive: true);
        }
        await _copyDirectory(Directory(qrSourceDir), qrTarget);
      }

      if (imagesSourceDir != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesTarget = Directory(p.join(appDir.path, 'images'));
        if (await imagesTarget.exists()) {
          await imagesTarget.delete(recursive: true);
        }
        await _copyDirectory(Directory(imagesSourceDir), imagesTarget);
      }

      if (attachmentsSourceDir != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final attachmentsTarget = Directory(p.join(appDir.path, 'attachments'));
        if (await attachmentsTarget.exists()) {
          await attachmentsTarget.delete(recursive: true);
        }
        await _copyDirectory(Directory(attachmentsSourceDir), attachmentsTarget);
      }

      // Re-open the database and verify the restored file is structurally
      // sound before declaring success.  A torn copy (e.g. the source was
      // modified mid-copy) would otherwise leave the app running against
      // a corrupt database.
      final reopened = await _dbHelper.database;
      final integrityRows = await reopened.rawQuery('PRAGMA integrity_check');
      final integrityResult =
          integrityRows.isEmpty ? '' : integrityRows.first.values.first;
      if (integrityResult != 'ok') {
        _log('Post-restore integrity_check failed: $integrityResult');
        return (false,
            'The restored database failed an integrity check: $integrityResult');
      }
      return (true, null);
    } on FileSystemException catch (e) {
      _log('Failed to copy backup to database path: ${e.message}');
      return (false, 'Could not copy backup to the database location: ${e.message}');
    } catch (e) {
      _log('Failed to copy backup to database path: $e');
      return (false, 'Could not copy backup to the database location: $e');
    } finally {
      if (extractedDir != null) {
        await _safeDeleteDir(Directory(extractedDir));
      }
    }
  }

  Future<String?> _createSafetyBackup() async {
    final db = await _dbHelper.database;
    final dbPath = db.path;
    final tempPath = await _tempPath('pinoy_pos_safety_backup.db');

    // Flush WAL into the main file before copying so the safety backup
    // captures the latest committed state.
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e) {
      _log('WAL checkpoint before safety backup failed (non-fatal): $e');
    }

    await _dbHelper.close();
    await _safeDelete(File(tempPath));
    try {
      await File(dbPath).copy(tempPath);
      return tempPath;
    } on FileSystemException catch (e) {
      _log('Failed to create safety backup: ${e.message}');
      return null;
    } catch (e) {
      _log('Failed to create safety backup: $e');
      return null;
    } finally {
      await _dbHelper.database;
    }
  }

  // ── Backup creation internals ────────────────────────────────────────

  Future<String> _prepareBackupFile() async {
    final db = await _dbHelper.database;
    final dbPath = db.path;
    _log('Resolved live database path for backup: $dbPath');

    // Checkpoint the WAL (if active) so all committed transactions are
    // flushed into the main database file before we copy it.  Without
    // this, a WAL-mode database could produce a backup that is missing
    // the most recent writes stored only in the -wal file.
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e) {
      _log('WAL checkpoint before backup failed (non-fatal): $e');
    }

    // Close the live connection before copying the file. On Windows the
    // open database file is locked while the connection is active, which
    // causes the copy to fail.
    await _dbHelper.close();

    String? tempDbPath;
    try {
      tempDbPath = await _tempPath('pinoy_pos_backup_${_timestamp()}.db');
      _log('Copying database to temp backup: $tempDbPath');
      await _safeDelete(File(tempDbPath));
      await File(dbPath).copy(tempDbPath);
      await _writeBackupMetadata(tempDbPath);

      final tempFile = File(tempDbPath);
      final stat = await tempFile.stat();
      if (stat.size == 0) {
        await _safeDelete(tempFile);
        throw _BackupServiceException('The prepared backup file was empty.');
      }

      return tempDbPath;
    } on _BackupServiceException {
      rethrow;
    } on FileSystemException catch (e) {
      _log('Failed to prepare backup file: ${e.message} (path: ${e.path})');
      throw _BackupServiceException(
        'Could not prepare the backup file. ${e.message}${e.path != null ? ' (${e.path})' : ''}',
      );
    } catch (e) {
      _log('Failed to prepare backup file: $e');
      throw _BackupServiceException('Could not prepare the backup file: $e');
    } finally {
      if (tempDbPath != null) {
        // The copied database may have left WAL/SHM/journal files behind in
        // the temp directory.  Clean those up so we do not leak auxiliary
        // SQLite files. The .db file itself must be kept because it is the
        // backup payload.
        for (final suffix in ['-wal', '-shm', '-journal']) {
          await _safeDelete(File('$tempDbPath$suffix'));
        }
      }
      // Reopen the database so the app can keep using it.
      await _dbHelper.database;
    }
  }

  Future<void> _writeBackupMetadata(String backupPath) async {
    Database? backupDb;
    try {
      // Open the copied database with the correct version.  Without an
      // explicit version, sqflite treats the request as version 1 and may
      // throw a downgrade error when the copied database is already at the
      // current schema version.
      backupDb = await openDatabase(
        backupPath,
        version: constants.AppConstants.databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) {},
        onUpgrade: (db, oldVersion, newVersion) {},
      );

      // Switch to a classic rollback journal so the metadata is written into
      // the main .db file and we do not leave a -wal file next to it.
      await backupDb.execute('PRAGMA journal_mode = DELETE');

      await backupDb.execute('''
        CREATE TABLE IF NOT EXISTS backup_metadata (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          app_name TEXT NOT NULL,
          app_version TEXT NOT NULL,
          database_version INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await backupDb.insert(
        'backup_metadata',
        {
          'id': 1,
          'app_name': constants.AppConstants.appName,
          'app_version': constants.AppConstants.appVersion,
          'database_version': constants.AppConstants.databaseVersion,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await backupDb.close();
    } catch (e) {
      _log('Failed to write backup metadata: $e');
      await _safeClose(backupDb);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await source.exists()) return;
    await target.create(recursive: true);

    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      final dest = p.join(target.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(dest));
      } else if (entity is File) {
        await entity.copy(dest);
      }
    }
  }

  Future<void> _safeDeleteDir(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      _log('Could not delete temp directory "${dir.path}": $e');
    }
  }

  String _generateBackupFileName() {
    // The canonical default filename for a Pinoy POS database backup.
    // The storage layer may append a numeric suffix if the same folder
    // already contains a file with this name.
    return 'pinoy_pos.db';
  }

  String _timestamp() {
    final now = DateTime.now();
    return now.toIso8601String().replaceAll(':', '-');
  }

  Future<String> _tempPath(String fileName) async {
    if (kIsWeb) {
      final dbDir = await getDatabasesPath();
      return p.join(dbDir, fileName);
    }
    final tempDir = await getTemporaryDirectory();
    return p.join(tempDir.path, fileName);
  }

  Future<String> _tempDir(String dirName) async {
    if (kIsWeb) {
      final dbDir = await getDatabasesPath();
      return p.join(dbDir, dirName);
    }
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, dirName));
    await dir.create(recursive: true);
    return dir.path;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Future<void> _logRestoreSuccess(String displayName) async {
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORED',
        entity: 'backup',
        details: 'Successfully restored from: $displayName',
      );
    } catch (e) {
      _log('Failed to log restore success: $e');
    }

    try {
      await _notificationService.createNotification(
        title: 'Backup Restored',
        message: 'Your Pinoy POS data has been restored successfully.',
        type: 'backup',
      );
    } catch (e) {
      _log('Failed to create restore notification: $e');
    }
  }

  Future<void> _logRestoreFailure(String displayName) async {
    try {
      await _activityLogService.logActivity(
        action: 'BACKUP_RESTORE_FAILED',
        entity: 'backup',
        details: 'Restore failed for: $displayName',
      );
    } catch (e) {
      _log('Failed to log restore failure: $e');
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      _log('Could not delete file "${file.path}": $e');
    }
  }

  Future<void> _safeClose(Database? db) async {
    try {
      await db?.close();
    } catch (e) {
      // Ignore.
    }
  }

  Future<bool> _hasTable(Database db, String table) async {
    final tables = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', table],
    );
    return tables.isNotEmpty;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  BackupStorageType _typeFromString(String? value) {
    if (value == null || value.isEmpty) return BackupStorageType.fileSystem;
    try {
      return BackupStorageType.values.byName(value);
    } catch (e) {
      return BackupStorageType.fileSystem;
    }
  }

  bool _isContentUri(String reference) {
    return reference.startsWith('content://');
  }

  bool _isFileUri(String reference) {
    return reference.startsWith('file://');
  }

  /// Decodes a `file://` URI into a local path, or returns [reference]
  /// unchanged if it is already a plain path.
  ///
  /// Returns `null` for any other URI scheme because it cannot be passed
  /// safely to Dart [File] operations.
  String? _toLocalPath(String reference) {
    if (!reference.contains('://')) return reference;
    if (!_isFileUri(reference)) return null;
    try {
      final uri = Uri.parse(reference);
      if (uri.scheme == 'file') return uri.toFilePath();
    } catch (e) {
      _log('Could not decode file URI: $reference');
    }
    return null;
  }

  /// Migrates a v1 plain-path stored reference into a typed [BackupLocation].
  ///
  /// The legacy value could be an absolute path, a `file://` URI, or a
  /// content URI from an older Android build, so we normalise it before
  /// storing it as the canonical v2 location.
  BackupLocation _migrateLegacyLocation(String legacy) {
    if (_isContentUri(legacy)) {
      return BackupLocation(
        type: BackupStorageType.androidSaf,
        reference: legacy,
        displayName: _storage.getLocationDisplayName(
          BackupLocation(
            type: BackupStorageType.androidSaf,
            reference: legacy,
            displayName: '',
          ),
        ),
      );
    }

    final path = _toLocalPath(legacy);
    if (path != null && path.isNotEmpty) {
      return BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: path,
        displayName: _storage.getLocationDisplayName(
          BackupLocation(
            type: BackupStorageType.fileSystem,
            reference: path,
            displayName: '',
          ),
        ),
      );
    }

    return const BackupLocation.none();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[BackupService] $message');
    }
  }
}


