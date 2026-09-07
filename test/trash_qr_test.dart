import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/secure_storage_test_helper.dart';

class _FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  _FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late PathProviderPlatform originalProvider;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    originalProvider = PathProviderPlatform.instance;
    appDir = await Directory.systemTemp.createTemp('pinoy_pos_trash_qr_');
    PathProviderPlatform.instance = _FakePathProvider(appDir);
  });

  tearDownAll(() async {
    if (await appDir.exists()) {
      await appDir.delete(recursive: true);
    }
    PathProviderPlatform.instance = originalProvider;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageTestHelper.setUp();
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(seconds: 1));

    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();

    final seeder = DatabaseSeeder();
    await seeder.seed();

    final owner = await dbHelper.database.then((db) async {
      final maps = await db.query(
        'users',
        where: 'role = ?',
        whereArgs: [UserRole.owner.name],
        limit: 1,
      );
      return maps.isNotEmpty ? User.fromMap(maps.first) : null;
    });
    if (owner != null) {
      SessionManager().setCurrentUser(owner);
    }

    // Register the QR restore handler.
    SettingsService();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(seconds: 2));
    SessionManager.resetForTest();
  });

  Future<String> writeQrFile() async {
    final dir = Directory(p.join(appDir.path, 'gcash_qr'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'test.png'));
    // Minimal PNG header bytes.
    final pngBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]);
    await file.writeAsBytes(pngBytes, flush: true);
    return 'gcash_qr/test.png';
  }

  test('moving and restoring a merchant QR image preserves the physical file',
      () async {
    final qrPath = await writeQrFile();
    const qrType = 'image/png';

    // Put the QR path into settings.
    final settingsService = SettingsService();
    final current = await settingsService.getSettings();
    await settingsService.updateSettings(
      current.copyWith(
        gcashQrImagePath: qrPath,
        gcashQrImageType: qrType,
      ),
    );

    // Move the QR image to trash; the physical file must stay intact.
    final moveResult = await TrashService().moveQrToTrash(qrPath, qrType);
    expect(moveResult.success, isTrue);

    final fileBefore = File(p.join(appDir.path, qrPath));
    expect(await fileBefore.exists(), isTrue);

    final trashItems = await TrashService().getAllTrash();
    final qrTrash = trashItems.firstWhere(
      (i) => i.entityType == 'merchant_qr',
    );
    expect(qrTrash, isNotNull);
    expect(qrTrash.attachmentCount, 1);
    expect(qrTrash.snapshotMap?['path'], qrPath);
    expect(qrTrash.snapshotMap?['type'], qrType);

    // Physical file should still be present while in trash.
    final fileInTrash = File(p.join(appDir.path, qrPath));
    expect(await fileInTrash.exists(), isTrue);

    // Restore the QR; settings should point back to the original path/type.
    final restoreResult = await TrashService().restoreFromTrash(qrTrash.id!);
    expect(restoreResult.success, isTrue);

    final restored = await settingsService.getSettings();
    expect(restored.gcashQrImagePath, qrPath);
    expect(restored.gcashQrImageType, qrType);

    // After restore the trash row is gone, but the physical file remains.
    final trashAfter = await TrashService().getAllTrash();
    expect(
      trashAfter.where((i) => i.entityType == 'merchant_qr').length,
      0,
    );
    expect(File(p.join(appDir.path, qrPath)).existsSync(), isTrue);
  });

  test('moveQrToTrash inserts a new row each time and never replaces existing',
      () async {
    final qrPath = await writeQrFile();

    await TrashService().moveQrToTrash(qrPath, 'image/png');
    await TrashService().moveQrToTrash(qrPath, 'image/png');

    final trashItems = await TrashService().getAllTrash();
    final qrRows =
        trashItems.where((i) => i.entityType == 'merchant_qr').toList();

    expect(qrRows.length, 2);
    expect(File(p.join(appDir.path, qrPath)).existsSync(), isTrue);

    // Permanently delete one of the QR trash rows.
    final deleteResult = await TrashService().permanentDelete(qrRows.first.id!);
    expect(deleteResult.success, isTrue);

    // The physical file should be deleted.
    expect(File(p.join(appDir.path, qrPath)).existsSync(), isFalse);

    // The remaining QR trash row should still exist.
    final remaining = await TrashService().getAllTrash();
    expect(
      remaining.where((i) => i.entityType == 'merchant_qr').length,
      1,
    );
  });
}
