import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/services/payment_qr_service.dart';
import 'package:qr/qr.dart';

class _FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  _FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;
}

/// Renders a valid QR code into an [img.Image] with the requested padding,
/// mimicking a merchant upload that contains extra information around the QR.
img.Image _generateQrImage({
  required int size,
  required int qrSize,
  required int offsetX,
  required int offsetY,
  String data = 'test-payment',
}) {
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  );
  final qrImage = QrImage(qrCode);

  final image = img.Image(
    width: size,
    height: size,
    numChannels: 4,
  );
  // White background.
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

  final moduleSize = qrSize ~/ qrImage.moduleCount;
  final startX = offsetX;
  final startY = offsetY;

  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var col = 0; col < qrImage.moduleCount; col++) {
      if (qrImage.isDark(row, col)) {
        img.fillRect(
          image,
          x1: startX + col * moduleSize,
          y1: startY + row * moduleSize,
          x2: startX + (col + 1) * moduleSize,
          y2: startY + (row + 1) * moduleSize,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      }
    }
  }

  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentQrService', () {
    late Directory appDir;
    late PathProviderPlatform originalProvider;
    final service = PaymentQrService();

    setUpAll(() async {
      originalProvider = PathProviderPlatform.instance;
      appDir = await Directory.systemTemp.createTemp('pinoy_pos_qr_test_');
      PathProviderPlatform.instance = _FakePathProvider(appDir);
    });

    tearDownAll(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
      PathProviderPlatform.instance = originalProvider;
    });

    Future<String> writePng(
      String relativeDir,
      String fileName,
      img.Image source,
    ) async {
      final dir = Directory(p.join(appDir.path, relativeDir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(img.encodePng(source), flush: true);
      return p.join(relativeDir, fileName);
    }

    test('detects a centered QR and generates a smaller cropped preview', () async {
      final source = _generateQrImage(
        size: 400,
        qrSize: 200,
        offsetX: 100,
        offsetY: 100,
      );
      final originalPath = await writePng('gcash_qr', 'centered.png', source);

      final result = await service.generatePreview(originalPath);

      expect(result.wasDetected, isTrue);
      expect(result.previewPath, isNotNull);
      expect(result.previewPath, isNot(equals(originalPath)));

      final previewFile = File(p.join(appDir.path, result.previewPath!));
      expect(await previewFile.exists(), isTrue);

      final previewImage = img.decodeImage(await previewFile.readAsBytes())!;
      // The preview must include the QR plus a safe margin, so it should be
      // larger than the raw 200×200 QR but smaller than the 400×400 source.
      expect(previewImage.width, lessThanOrEqualTo(source.width));
      expect(previewImage.height, lessThanOrEqualTo(source.height));
      expect(previewImage.width, greaterThan(100));
      expect(previewImage.height, greaterThan(100));
    });

    test('detects a QR placed near the top of the image', () async {
      final source = _generateQrImage(
        size: 400,
        qrSize: 160,
        offsetX: 120,
        offsetY: 20,
      );
      final originalPath = await writePng('gcash_qr', 'top.png', source);

      final result = await service.generatePreview(originalPath);

      expect(result.wasDetected, isTrue);
      expect(result.previewPath, isNotNull);
    });

    test('detects a QR placed near the bottom of the image', () async {
      final source = _generateQrImage(
        size: 400,
        qrSize: 160,
        offsetX: 120,
        offsetY: 220,
      );
      final originalPath = await writePng('gcash_qr', 'bottom.png', source);

      final result = await service.generatePreview(originalPath);

      expect(result.wasDetected, isTrue);
      expect(result.previewPath, isNotNull);
    });

    test('detects a small QR and enlarges it in the preview', () async {
      final source = _generateQrImage(
        size: 600,
        qrSize: 120,
        offsetX: 80,
        offsetY: 80,
      );
      final originalPath = await writePng('gcash_qr', 'small.png', source);

      final result = await service.generatePreview(originalPath);

      expect(result.wasDetected, isTrue);
      expect(result.previewPath, isNotNull);
    });

    test('falls back to the original image when no QR is present', () async {
      final image = img.Image(
        width: 200,
        height: 200,
        numChannels: 4,
      );
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
      final originalPath = await writePng('gcash_qr', 'no_qr.png', image);

      final result = await service.generatePreview(originalPath);

      expect(result.wasDetected, isFalse);
      expect(result.originalPath, equals(originalPath));
      expect(result.previewPath, isNull);
    });

    test('deletes an obsolete preview without removing the original', () async {
      final source = _generateQrImage(
        size: 400,
        qrSize: 200,
        offsetX: 100,
        offsetY: 100,
      );
      final originalPath = await writePng('gcash_qr', 'old.png', source);
      final first = await service.generatePreview(originalPath);
      expect(first.previewPath, isNotNull);

      await service.deletePreviewForOriginal(originalPath);

      final previewFile = File(p.join(appDir.path, first.previewPath!));
      expect(await previewFile.exists(), isFalse);

      final originalFile = File(p.join(appDir.path, originalPath));
      expect(await originalFile.exists(), isTrue);
    });

    test('decodes an EMVCo payment QR payload from an uploaded image',
        () async {
      // GCash-style QR Ph P2M payload with a real CRC-16 checksum.
      const payload =
          '00020101021126470011ph.ppmi.p2m01126399524112340212GcashXchange'
          '5204541153036085802PH5911Mi**** L T.6006Manila'
          '622802126399524112340508BILL-00163046186';
      final source = _generateQrImage(
        size: 700,
        qrSize: 500,
        offsetX: 100,
        offsetY: 100,
        data: payload,
      );
      final originalPath = await writePng('gcash_qr', 'emv.png', source);

      final decoded = await service.decodePaymentQr(originalPath);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.merchantName, 'Mi**** L T.');
      expect(decoded.mobileNumber, '+63 995 241 1234');
      expect(decoded.paymentNetwork, 'QR Ph');
      expect(decoded.currencyCode, 'PHP');
    });

    test('reports a non-payment QR payload as decoded but unrecognized',
        () async {
      final source = _generateQrImage(
        size: 400,
        qrSize: 300,
        offsetX: 50,
        offsetY: 50,
        data: 'https://example.com/not-a-payment',
      );
      final originalPath = await writePng('gcash_qr', 'url.png', source);

      final decoded = await service.decodePaymentQr(originalPath);

      expect(decoded.status, PaymentQrDecodeStatus.decodedUnparsed);
      expect(decoded.merchantName, isNull);
      expect(decoded.mobileNumber, isNull);
    });

    test('reports notDetected when the image contains no QR', () async {
      final image = img.Image(
        width: 200,
        height: 200,
        numChannels: 4,
      );
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
      final originalPath = await writePng('gcash_qr', 'blank.png', image);

      final decoded = await service.decodePaymentQr(originalPath);

      expect(decoded.status, PaymentQrDecodeStatus.notDetected);
      expect(decoded.hasAnyDetails, isFalse);
    });

    test('reports notDetected for a missing QR path', () async {
      final decoded = await service.decodePaymentQr(null);
      expect(decoded.status, PaymentQrDecodeStatus.notDetected);
    });

    test('replaces an old preview when a new original is uploaded', () async {
      final oldSource = _generateQrImage(
        size: 400,
        qrSize: 200,
        offsetX: 100,
        offsetY: 100,
      );
      final oldPath = await writePng('gcash_qr', 'old2.png', oldSource);
      final oldResult = await service.generatePreview(oldPath);

      final newSource = _generateQrImage(
        size: 400,
        qrSize: 200,
        offsetX: 120,
        offsetY: 80,
      );
      final newPath = await writePng('gcash_qr', 'new2.png', newSource);

      await service.deletePreviewForOriginal(oldPath);
      final newResult = await service.generatePreview(newPath);

      final oldPreviewFile = File(p.join(appDir.path, oldResult.previewPath!));
      expect(await oldPreviewFile.exists(), isFalse);

      final newPreviewFile = File(p.join(appDir.path, newResult.previewPath!));
      expect(await newPreviewFile.exists(), isTrue);
    });
  });
}
