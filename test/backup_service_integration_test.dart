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
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
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
    appDir = await Directory.systemTemp.createTemp('pinoy_pos_backup_test_');
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
    await Future.delayed(const Duration(milliseconds: 500));
  });

  Future<void> authAsAdmin() async {
    final authService = AuthService();
    final result = await authService.login('admin', 'admin123');
    if (result != LoginResult.success) {
      throw StateError('Admin login failed: $result');
    }
  }

  group('BackupService export', () {
    test('Admin can export a backup using the default desktop location', () async {
      await authAsAdmin();
      await ProductRepository().insert(Product(
        name: 'Test Product',
        price: 100.0,
        stock: 10,
        createdAt: DateTime.now(),
      ));

      final backupService = BackupService();
      final result = await backupService.exportBackup();

      expect(result.result, BackupExportResult.success, reason: result.error);
      expect(result.fileSize, greaterThan(0), reason: 'Backup file must not be empty');
      expect(result.storageReference, isNotNull);
      expect(await File(result.storageReference!).exists(), isTrue);
      expect(await File(result.storageReference!).length(), greaterThan(0));
    });

    test('Admin can export a real SQLite .db backup', () async {
      await authAsAdmin();

      final targetDir = Directory(p.join(appDir.path, 'backups'));
      await targetDir.create(recursive: true);

      final backupService = BackupService();
      final location = BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: targetDir.path,
        displayName: 'Test backup folder',
      );

      final result = await backupService.exportBackup(override: location);

      expect(result.result, BackupExportResult.success, reason: result.error);
      expect(result.fileSize, greaterThan(0), reason: 'Backup file must not be empty');
      expect(result.storageReference, isNotNull);

      final file = File(result.storageReference!);
      expect(await file.exists(), isTrue, reason: 'Backup file does not exist on disk');
      expect(await file.length(), greaterThan(0), reason: 'Backup file on disk is empty');

      // Verify the exported file is a real SQLite .db file.
      expect(p.extension(file.path).toLowerCase(), '.db',
          reason: 'Backup must use .db extension');
      final raf = await file.open();
      final header = await raf.read(16);
      await raf.close();
      final headerStr = String.fromCharCodes(header);
      expect(headerStr, startsWith('SQLite format 3'),
          reason: 'Backup must be a valid SQLite database file');

      // It should contain the Pinoy POS backup metadata.
      final testDb = await openDatabase(file.path, readOnly: true);
      final metaRows = await testDb.query(
        'backup_metadata',
        where: 'id = 1',
        limit: 1,
      );
      expect(metaRows, isNotEmpty,
          reason: 'Backup metadata should be present');
      await testDb.close();
    });

    test('Exported backup can be restored and contains the expected data', () async {
      await authAsAdmin();

      // Seed real business data.
      await ProductRepository().insert(Product(
        name: 'Test Product',
        price: 100.0,
        stock: 10,
        createdAt: DateTime.now(),
      ));

      final targetDir = Directory(p.join(appDir.path, 'backups'));
      await targetDir.create(recursive: true);

      final backupService = BackupService();
      final export = await backupService.exportBackup(override: BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: targetDir.path,
        displayName: 'Test backup folder',
      ));

      expect(export.result, BackupExportResult.success, reason: export.error);

      // Modify data before restoring.
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.delete('products');

      final import = await backupService.restoreFromHistory(BackupHistory(
        filePath: export.storageReference!,
        displayName: export.displayName,
        fileSize: export.fileSize,
        createdAt: DateTime.now(),
      ));

      expect(import.result, BackupImportResult.success, reason: import.error);

      // After restore the deleted products should be back.
      final restoredDb = await DatabaseHelper().database;
      final products = await restoredDb.query('products');
      expect(products, isNotEmpty, reason: 'Restored database should still contain products');
    });
  });
}
