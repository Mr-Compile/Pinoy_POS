import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';

void main() {
  group('PaymentProofService.resolveImageExtension', () {
    test('uses detected image file type extension', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof.png'),
        fileType: FileType.png,
        sizeBytes: 100,
        originalName: 'proof.png',
      );
      expect(PaymentProofService.resolveImageExtension(info), 'png');
    });

    test('falls back to extension from original name when detection is null', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof.webp'),
        fileType: null,
        sizeBytes: 100,
        originalName: 'proof.webp',
      );
      expect(PaymentProofService.resolveImageExtension(info), 'webp');
    });

    test('maps .jpeg original name to canonical jpg', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof.jpeg'),
        fileType: null,
        sizeBytes: 100,
        originalName: 'proof.jpeg',
      );
      expect(PaymentProofService.resolveImageExtension(info), 'jpg');
    });

    test('falls back to jpg when neither type nor name provide an image extension', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof'),
        fileType: null,
        sizeBytes: 100,
        originalName: 'proof',
      );
      expect(PaymentProofService.resolveImageExtension(info), 'jpg');
    });

    test('falls back to jpg for a non-image original name', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof.pdf'),
        fileType: null,
        sizeBytes: 100,
        originalName: 'proof.pdf',
      );
      expect(PaymentProofService.resolveImageExtension(info), 'jpg');
    });
  });

  group('PaymentProofInfo', () {
    test('isImage is true for image file types', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof.jpg'),
        fileType: FileType.jpeg,
        sizeBytes: 100,
        originalName: 'proof.jpg',
      );
      expect(info.isImage, isTrue);
      expect(info.isPdf, isFalse);
    });

    test('isImage is false when fileType is null', () {
      final info = PaymentProofInfo(
        file: File('/tmp/proof'),
        fileType: null,
        sizeBytes: 100,
        originalName: 'proof',
      );
      expect(info.isImage, isFalse);
      expect(info.isPdf, isFalse);
    });

    test('isPdf is true for pdf file type', () {
      final info = PaymentProofInfo(
        file: File('/tmp/receipt.pdf'),
        fileType: FileType.pdf,
        sizeBytes: 100,
        originalName: 'receipt.pdf',
      );
      expect(info.isImage, isFalse);
      expect(info.isPdf, isTrue);
    });
  });
}
