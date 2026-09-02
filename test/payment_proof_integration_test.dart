import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;
import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';

class FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentProofService real file resolution', () {
    late Directory appDir;
    late PathProviderPlatform originalProvider;

    setUpAll(() async {
      originalProvider = PathProviderPlatform.instance;
      appDir = await Directory.systemTemp.createTemp('pinoy_pos_proof_test_');
      PathProviderPlatform.instance = FakePathProvider(appDir);
    });

    tearDownAll(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
      // Restore the original platform implementation so other tests are
      // not affected.
      PathProviderPlatform.instance = originalProvider;
    });

    Future<String> writeProofFile(
      String relativeDir,
      String fileName,
      Uint8List bytes,
    ) async {
      final dir = Directory(p.join(appDir.path, relativeDir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return p.join(relativeDir, fileName);
    }

    test('resolves a no-extension JPEG proof by magic bytes', () async {
      final jpegBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00,
      ]);
      final relativePath = await writeProofFile(
        'payment_evidence/sale_99991',
        'proof',
        jpegBytes,
      );

      final info = await PaymentProofService().resolveProofFromPath(relativePath);

      expect(info, isNotNull);
      expect(info!.isImage, isTrue);
      expect(info.fileType, FileType.jpeg);
      expect(PaymentProofService.resolveImageExtension(info), 'jpg');
    });

    test('resolves a no-extension PNG proof by magic bytes', () async {
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ]);
      final relativePath = await writeProofFile(
        'payment_evidence/sale_99992',
        'proof',
        pngBytes,
      );

      final info = await PaymentProofService().resolveProofFromPath(relativePath);

      expect(info, isNotNull);
      expect(info!.isImage, isTrue);
      expect(info.fileType, FileType.png);
      expect(PaymentProofService.resolveImageExtension(info), 'png');
    });

    test('ImageService.detectFileType handles a path without extension', () async {
      final jpegBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x18, 0x45, 0x78,
        0x69, 0x66, 0x00, 0x00, 0x49, 0x49, 0x2A, 0x00,
      ]);
      final relativePath = await writeProofFile(
        'payment_evidence/sale_99993',
        'gcash_proof',
        jpegBytes,
      );

      final fileType = await ImageService().detectFileType(relativePath);

      expect(fileType, isNotNull);
      expect(fileType!.isImage, isTrue);
      expect(fileType.mime, 'image/jpeg');
      expect(fileType.extension, 'jpg');
    });
  });
}
