import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AuthService _authService = AuthService();

  Future<String> createBackup() async {
    if (!_authService.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    final db = await _dbHelper.database;
    final dbPath = db.path;

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = join(directory.path, 'pinoy_pos_backup_$timestamp.db');

    await File(dbPath).copy(backupPath);
    return backupPath;
  }

  Future<bool> restoreBackup(String backupPath) async {
    if (!_authService.hasPermission('backup_restore')) {
      throw AuthorizationException('backup_restore');
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = join(directory.path, 'pinoy_pos.db');

      await File(backupPath).copy(dbPath);

      await _dbHelper.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}
