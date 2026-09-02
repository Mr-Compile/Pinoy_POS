import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/file_type_utils.dart';

void main() {
  group('FileType.fromExtension', () {
    test('maps .jpg to jpeg', () {
      final type = FileType.fromExtension('proof.jpg');
      expect(type, FileType.jpeg);
      expect(type?.extension, 'jpg');
      expect(type?.mime, 'image/jpeg');
    });

    test('maps .jpeg to jpeg', () {
      final type = FileType.fromExtension('proof.jpeg');
      expect(type, FileType.jpeg);
      expect(type?.extension, 'jpg');
    });

    test('maps .jpe and .jfif to jpeg', () {
      expect(FileType.fromExtension('proof.jpe'), FileType.jpeg);
      expect(FileType.fromExtension('proof.jfif'), FileType.jpeg);
    });

    test('maps .png to png', () {
      final type = FileType.fromExtension('proof.png');
      expect(type, FileType.png);
      expect(type?.extension, 'png');
    });

    test('maps .webp to webp', () {
      final type = FileType.fromExtension('proof.webp');
      expect(type, FileType.webp);
    });

    test('maps .gif to gif', () {
      final type = FileType.fromExtension('proof.gif');
      expect(type, FileType.gif);
    });

    test('maps .bmp to bmp', () {
      final type = FileType.fromExtension('proof.bmp');
      expect(type, FileType.bmp);
    });

    test('maps .tiff and .tif to tiff', () {
      expect(FileType.fromExtension('proof.tiff'), FileType.tiff);
      expect(FileType.fromExtension('proof.tif'), FileType.tiff);
    });

    test('maps .heic and .heif to heic', () {
      expect(FileType.fromExtension('proof.heic'), FileType.heic);
      expect(FileType.fromExtension('proof.heif'), FileType.heic);
    });

    test('maps .avif to avif', () {
      expect(FileType.fromExtension('proof.avif'), FileType.avif);
    });

    test('maps .svg to svg', () {
      expect(FileType.fromExtension('proof.svg'), FileType.svg);
    });

    test('maps .pdf to pdf', () {
      final type = FileType.fromExtension('receipt.pdf');
      expect(type, FileType.pdf);
    });

    test('returns null for an unknown extension', () {
      expect(FileType.fromExtension('proof.xyz'), isNull);
    });

    test('returns null for an extensionless filename', () {
      expect(FileType.fromExtension('proof'), isNull);
    });
  });

  group('FileType.fromMime', () {
    test('maps image/jpeg to jpeg', () {
      expect(FileType.fromMime('image/jpeg'), FileType.jpeg);
    });

    test('maps image/png to png', () {
      expect(FileType.fromMime('image/png'), FileType.png);
    });

    test('maps application/pdf to pdf', () {
      expect(FileType.fromMime('application/pdf'), FileType.pdf);
    });

    test('returns null for an unknown mime', () {
      expect(FileType.fromMime('application/octet-stream'), isNull);
    });
  });

  group('FileTypeUtils.detect', () {
    test('detects JPEG from magic bytes', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.jpeg);
    });

    test('detects PNG from magic bytes', () {
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.png);
    });

    test('detects WebP from RIFF/WEBP', () {
      final bytes = Uint8List(12);
      bytes[0] = 0x52; // R
      bytes[1] = 0x49; // I
      bytes[2] = 0x46; // F
      bytes[3] = 0x46; // F
      bytes[8] = 0x57; // W
      bytes[9] = 0x45; // E
      bytes[10] = 0x42; // B
      bytes[11] = 0x50; // P
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.webp);
    });

    test('detects GIF from magic bytes', () {
      final bytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
      ]);
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.gif);
    });

    test('detects BMP from magic bytes', () {
      final bytes = Uint8List.fromList([0x42, 0x4D, 0x00, 0x00]);
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.bmp);
    });

    test('detects TIFF little-endian', () {
      final bytes = Uint8List.fromList([0x49, 0x49, 0x2A, 0x00]);
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.tiff);
    });

    test('detects HEIC from ftyp brand', () {
      final bytes = Uint8List(16);
      bytes[4] = 0x66; // f
      bytes[5] = 0x74; // t
      bytes[6] = 0x79; // y
      bytes[7] = 0x70; // p
      const brand = 'heic';
      for (var i = 0; i < brand.length; i++) {
        bytes[8 + i] = brand.codeUnitAt(i);
      }
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.heic);
    });

    test('detects AVIF from ftyp brand', () {
      final bytes = Uint8List(16);
      bytes[4] = 0x66; // f
      bytes[5] = 0x74; // t
      bytes[6] = 0x79; // y
      bytes[7] = 0x70; // p
      const brand = 'avif';
      for (var i = 0; i < brand.length; i++) {
        bytes[8 + i] = brand.codeUnitAt(i);
      }
      final type = FileTypeUtils.detect(bytes, fileName: 'unknown');
      expect(type, FileType.avif);
    });

    test('detects SVG from XML header', () {
      final bytes = Uint8List.fromList(
        '<?xml version="1.0"?><svg'.codeUnits,
      );
      final type = FileTypeUtils.detect(bytes, fileName: 'vector');
      expect(type, FileType.svg);
    });

    test('detects PDF from magic bytes', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
      final type = FileTypeUtils.detect(bytes, fileName: 'document');
      expect(type, FileType.pdf);
    });

    test('falls back to filename extension when bytes are unrecognised', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final type = FileTypeUtils.detect(bytes, fileName: 'proof.png');
      expect(type, FileType.png);
    });

    test('returns null for unrecognised bytes and no filename', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final type = FileTypeUtils.detect(bytes);
      expect(type, isNull);
    });

    test('detects JPEG even with no filename extension', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x00]);
      final type = FileTypeUtils.detect(bytes, fileName: '1000001234');
      expect(type, FileType.jpeg);
      expect(type?.extension, 'jpg');
    });
  });

  group('FileTypeUtils helpers', () {
    test('extensionForMime returns canonical extension', () {
      expect(FileTypeUtils.extensionForMime('image/jpeg'), 'jpg');
      expect(FileTypeUtils.extensionForMime('image/png'), 'png');
      expect(FileTypeUtils.extensionForMime('application/pdf'), 'pdf');
      expect(FileTypeUtils.extensionForMime(null), isNull);
    });

    test('mimeForExtension returns canonical mime', () {
      expect(FileTypeUtils.mimeForExtension('jpg'), 'image/jpeg');
      expect(FileTypeUtils.mimeForExtension('jpeg'), 'image/jpeg');
      expect(FileTypeUtils.mimeForExtension('png'), 'image/png');
      expect(FileTypeUtils.mimeForExtension('pdf'), 'application/pdf');
      expect(FileTypeUtils.mimeForExtension(null), isNull);
    });

    test('isImage recognises image MIMEs', () {
      expect(FileTypeUtils.isImage('image/jpeg'), isTrue);
      expect(FileTypeUtils.isImage('image/png'), isTrue);
      expect(FileTypeUtils.isImage('application/pdf'), isFalse);
      expect(FileTypeUtils.isImage(null), isFalse);
    });

    test('isPdf recognises pdf MIME', () {
      expect(FileTypeUtils.isPdf('application/pdf'), isTrue);
      expect(FileTypeUtils.isPdf('image/jpeg'), isFalse);
    });
  });
}
