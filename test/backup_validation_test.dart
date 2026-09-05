import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/data/models/backup_location.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/backup_service.dart';

class FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;

  @override
  Future<String?> getApplicationSupportPath() async => appDocs.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late PathProviderPlatform originalProvider;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    originalProvider = PathProviderPlatform.instance;
    appDir = await Directory.systemTemp.createTemp('pinoy_pos_backup_validation_');
    PathProviderPlatform.instance = FakePathProvider(appDir);
  });

  tearDownAll(() async {
    if (await appDir.exists()) {
      await appDir.delete(recursive: true);
    }
    PathProviderPlatform.instance = originalProvider;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();
    await DatabaseSeeder().seed();
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
  });

  Future<void> authAsAdmin() async {
    final authService = AuthService();
    final result = await authService.login('admin', 'admin123');
    if (result != LoginResult.success) {
      throw StateError('Admin login failed: $result');
    }
  }

  Future<String> copyLiveDbTo(String suffix) async {
    final dbHelper = DatabaseHelper();
    final livePath = await dbHelper.databasePath;
    await dbHelper.close();

    final copyPath = p.join(appDir.path, 'validation_backup_$suffix.db');
    await File(livePath).copy(copyPath);
    return copyPath;
  }

  group('BackupService validation', () {
    test('exported .db backup can be restored without being marked incompatible', () async {
      await authAsAdmin();

      final backupService = BackupService();
      final targetDir = Directory(p.join(appDir.path, 'backups'));
      await targetDir.create(recursive: true);

      final export = await backupService.exportBackup(
        override: BackupLocation(
          type: BackupStorageType.fileSystem,
          reference: targetDir.path,
          displayName: 'Test backup folder',
        ),
      );

      expect(export.result, BackupExportResult.success, reason: export.error);

      final import = await backupService.restoreFromHistory(BackupHistory(
        filePath: export.storageReference!,
        displayName: export.displayName,
        fileSize: export.fileSize,
        createdAt: DateTime.now(),
      ));

      expect(import.result, BackupImportResult.success, reason: import.error);
    });

    test('legacy .db without backup_metadata row is not rejected', () async {
      await authAsAdmin();

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      // Simulate a legacy backup where the backup_metadata table exists
      // but was never populated.
      await db.delete('backup_metadata');
      await dbHelper.close();

      final backupPath = await copyLiveDbTo('empty_metadata');

      final import = await BackupService().restoreFromHistory(BackupHistory(
        filePath: backupPath,
        displayName: 'legacy_no_metadata_row.db',
        fileSize: await File(backupPath).length(),
        createdAt: DateTime.now(),
      ));

      expect(import.result, isNot(BackupImportResult.incompatible), reason: import.error);
      expect(import.result, BackupImportResult.success, reason: import.error);
    });

    test('legacy .db missing backup_metadata table is not rejected', () async {
      await authAsAdmin();

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.execute('DROP TABLE IF EXISTS backup_metadata');
      await dbHelper.close();

      final backupPath = await copyLiveDbTo('missing_metadata_table');

      final import = await BackupService().restoreFromHistory(BackupHistory(
        filePath: backupPath,
        displayName: 'legacy_no_metadata_table.db',
        fileSize: await File(backupPath).length(),
        createdAt: DateTime.now(),
      ));

      expect(import.result, isNot(BackupImportResult.incompatible), reason: import.error);
      expect(import.result, BackupImportResult.success, reason: import.error);
    });

    test('non-Pinoy POS .db is rejected as incompatible', () async {
      await authAsAdmin();

      final fakePath = p.join(appDir.path, 'fake.db');
      final fakeDb = await openDatabase(fakePath, version: 1, onCreate: (db, version) async {
        await db.execute('CREATE TABLE foo (id INTEGER PRIMARY KEY)');
      });
      await fakeDb.close();

      final import = await BackupService().restoreFromHistory(BackupHistory(
        filePath: fakePath,
        displayName: 'fake.db',
        fileSize: await File(fakePath).length(),
        createdAt: DateTime.now(),
      ));

      expect(import.result, BackupImportResult.incompatible, reason: import.error);
    });
  });
}
