import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:qr/qr.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  _FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;
}

/// A GCash-style QR Ph P2M payload with a real CRC-16 checksum — same
/// sample used by the parser and service tests.
const _qrPhPayload =
    '00020101021126470011ph.ppmi.p2m01126399524112340212GcashXchange'
    '5204541153036085802PH5911Mi**** L T.6006Manila'
    '622802126399524112340508BILL-00163046186';

/// Renders a scannable QR code carrying [data] on a white background.
img.Image _generateQrImage(String data) {
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  );
  final qrImage = QrImage(qrCode);

  const size = 700;
  const qrSize = 500;
  const offset = 100;
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

  final moduleSize = qrSize ~/ qrImage.moduleCount;
  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var col = 0; col < qrImage.moduleCount; col++) {
      if (qrImage.isDark(row, col)) {
        img.fillRect(
          image,
          x1: offset + col * moduleSize,
          y1: offset + row * moduleSize,
          x2: offset + (col + 1) * moduleSize,
          y2: offset + (row + 1) * moduleSize,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      }
    }
  }
  return image;
}

/// Tests for the persisted payment-QR payload cache (DB v31): the decoded
/// payload lives on the settings row so payment screens never re-decode
/// the image after the first open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late PathProviderPlatform originalProvider;
  final service = SettingsService();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalProvider = PathProviderPlatform.instance;
    appDir = await Directory.systemTemp.createTemp('pinoy_pos_qr_cache_');
    PathProviderPlatform.instance = _FakePathProvider(appDir);
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

    await DatabaseHelper().recreateSchemaForTest();
    await DatabaseSeeder().seed();

    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
  });

  Future<Map<String, Object?>> settingsRow() async {
    final db = await DatabaseHelper().database;
    return (await db.query('settings')).single;
  }

  /// Inserts the single settings row with the given QR fields — the app
  /// creates it lazily, so tests seed it directly.
  Future<void> setQrColumns({
    String? imagePath,
    String? payload,
  }) async {
    final db = await DatabaseHelper().database;
    final now = DateTime.now().toIso8601String();
    await db.insert('settings', {
      'store_name': 'Test Store',
      'currency': 'PHP',
      'gcash_qr_image_path': imagePath,
      'gcash_qr_payload': payload,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<String> writeQrPng(String fileName, String data) async {
    final dir = Directory(p.join(appDir.path, 'gcash_qr'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(img.encodePng(_generateQrImage(data)),
        flush: true);
    return p.join('gcash_qr', fileName);
  }

  Future<User> userByUsername(String username) async {
    final db = await DatabaseHelper().database;
    final maps =
        await db.query('users', where: 'username = ?', whereArgs: [username]);
    return User.fromMap(maps.single);
  }

  group('getDecodedPaymentQr payload cache', () {
    test('serves the persisted payload without touching the image file',
        () async {
      // The image does not exist on disk — if the service tried to decode
      // it the result would be unreadable. Getting `recognized` proves the
      // database cache was used.
      await setQrColumns(
        imagePath: 'gcash_qr/missing.png',
        payload: _qrPhPayload,
      );

      final decoded =
          await service.getDecodedPaymentQr('gcash_qr/missing.png');

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.merchantName, 'Mi**** L T.');
      expect(decoded.mobileNumber, '+63 995 241 1234');
      expect(decoded.paymentNetwork, 'QR Ph');
    });

    test('decodes a real QR once and persists the payload for later opens',
        () async {
      final relPath = await writeQrPng('real.png', _qrPhPayload);
      await setQrColumns(imagePath: relPath);

      final decoded = await service.getDecodedPaymentQr(relPath);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.merchantName, 'Mi**** L T.');

      final row = await settingsRow();
      expect(row['gcash_qr_payload'], _qrPhPayload);
    });

    test('persists a failed decode so it does not retry on every open',
        () async {
      // File intentionally missing: decode fails, and the empty-string
      // cache entry must still be written so repeat opens stop retrying.
      await setQrColumns(imagePath: 'gcash_qr/missing.png');

      final decoded =
          await service.getDecodedPaymentQr('gcash_qr/missing.png');
      expect(decoded.isRecognized, isFalse);

      final row = await settingsRow();
      expect(row['gcash_qr_payload'], '');

      // A repeat open resolves through the cached (empty) payload.
      final again =
          await service.getDecodedPaymentQr('gcash_qr/missing.png');
      expect(again.isRecognized, isFalse);
      expect(again.hasAnyDetails, isFalse);
    });

    test('a payload cached for a different image is never used', () async {
      await setQrColumns(
        imagePath: 'gcash_qr/current.png',
        payload: _qrPhPayload,
      );

      final decoded =
          await service.getDecodedPaymentQr('gcash_qr/other.png');
      expect(decoded.isRecognized, isFalse);

      // The stored payload stays bound to the configured image.
      final row = await settingsRow();
      expect(row['gcash_qr_payload'], _qrPhPayload);
    });

    test('returns notDetected for an empty path', () async {
      final decoded = await service.getDecodedPaymentQr(null);
      expect(decoded.status, PaymentQrDecodeStatus.notDetected);
    });
  });

  group('QR removal clears the payload cache', () {
    test('clearGcashQrImage clears image and payload columns', () async {
      final owner = await userByUsername('owner');
      SessionManager().setCurrentUser(owner);

      await setQrColumns(
        imagePath: 'gcash_qr/missing.png',
        payload: _qrPhPayload,
      );

      await service.clearGcashQrImage();

      final row = await settingsRow();
      expect(row['gcash_qr_image_path'], isNull);
      expect(row['gcash_qr_preview_path'], isNull);
      expect(row['gcash_qr_payload'], isNull);
    });
  });
}
