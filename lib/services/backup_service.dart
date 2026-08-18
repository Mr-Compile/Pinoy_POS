import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/backup_history_dao.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SessionManager _sessionManager = SessionManager();
  final BackupHistoryDao _backupHistoryDao = BackupHistoryDao();

  Future<String> createBackup() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    final db = await _dbHelper.database;
    final dbPath = db.path;

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = join(directory.path, 'pinoy_pos_backup_$timestamp.db');

    await File(dbPath).copy(backupPath);

    final fileSize = await File(backupPath).length();
    await _backupHistoryDao.insert(BackupHistory(
      filePath: backupPath,
      fileSize: fileSize,
      createdBy: _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    ));

    return backupPath;
  }

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
    } catch (_) {}
    await _backupHistoryDao.delete(id);
    return true;
  }

  Future<bool> restoreBackup(String backupPath) async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    // Validate the backup file exists and is non-empty (basic corruption
    // guard). An empty or missing file cannot be a valid SQLite database.
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      return false;
    }
    final stat = await backupFile.stat();
    if (stat.size == 0) {
      return false;
    }

    // The live database lives at db.path (getDatabasesPath()/pinoy_pos.db),
    // which is NOT necessarily the same as getApplicationDocumentsDirectory().
    // Restore must overwrite the actual database file, not a sibling file in
    // a different directory.
    final db = await _dbHelper.database;
    final dbPath = db.path;

    // Close the database handle before overwriting its file so that the
    // file is not locked and the next access re-opens the restored data.
    await _dbHelper.close();

    try {
      await backupFile.copy(dbPath);
      return true;
    } catch (e) {
      return false;
    }
  }
}
