import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;

import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/services/file_export_service.dart';
import 'package:pinoy_pos/services/image_service.dart';

/// Resolved, type-checked payment proof ready for preview or export.
class PaymentProofInfo {
  /// The absolute file on disk.
  final File file;

  /// Detected file type (MIME, canonical extension, label).
  final FileType? fileType;

  /// File size in bytes.
  final int sizeBytes;

  /// Original stored filename without path.
  final String? originalName;

  const PaymentProofInfo({
    required this.file,
    this.fileType,
    required this.sizeBytes,
    this.originalName,
  });

  bool get isImage => fileType?.isImage ?? false;
  bool get isPdf => fileType?.isPdf ?? false;

  /// Loads the full file bytes. Call this when exporting or displaying PDFs.
  Future<Uint8List> readBytes() => file.readAsBytes();
}

/// Centralised resolve, type detection, preview support, and export for
/// payment proofs.
///
/// The service reuses [ImageService] for file resolution and storage and
/// [FileExportService] for save dialogs. It does not duplicate those systems.
class PaymentProofService {
  final ImageService _imageService = ImageService();

  /// Resolves a sale's payment proof to a [PaymentProofInfo] with the actual
  /// file type detected from magic bytes and filename fallback.
  ///
  /// Returns `null` if the sale has no proof or the file is missing.
  Future<PaymentProofInfo?> resolveProof(Sale sale) async {
    return resolveProofFromPath(sale.paymentProofPath);
  }

  /// Resolves a payment proof from its relative [path].
  ///
  /// This is useful for view models like [ReceiptViewData] that carry the
  /// proof path but not a full [Sale] object.
  Future<PaymentProofInfo?> resolveProofFromPath(String? path) async {
    if (path == null || path.isEmpty) return null;

    final file = await _imageService.resolveImageFile(path);
    if (file == null) return null;

    try {
      final fileType = await _imageService.detectFileType(path);
      final sizeBytes = await file.length();
      return PaymentProofInfo(
        file: file,
        fileType: fileType,
        sizeBytes: sizeBytes,
        originalName: p.basename(file.path),
      );
    } catch (_) {
      return null;
    }
  }

  /// Presents a save dialog for the payment proof and writes it in its
  /// original format.
  ///
  /// The filename is `payment_proof_<saleId>.<actualExt>` and the exported
  /// bytes are the original file contents. The extension matches the detected
  /// type, not an arbitrary label.
  ///
  /// Returns the saved path, or `null` if the user cancels or the file cannot
  /// be read.
  Future<String?> exportPaymentProof(Sale sale) async {
    return exportPaymentProofFromPath(sale.paymentProofPath, sale.id);
  }

  /// Exports a payment proof given its relative [path] and optional [saleId].
  Future<String?> exportPaymentProofFromPath(
    String? path,
    int? saleId,
  ) async {
    final info = await resolveProofFromPath(path);
    if (info == null) return null;

    final ext = info.fileType?.extension ??
        p.extension(info.originalName ?? '').replaceAll('.', '');
    final safeExt = ext.isNotEmpty ? ext : 'bin';
    final idSuffix = saleId != null ? '_$saleId' : '';
    final fileName = 'payment_proof$idSuffix.$safeExt';

    final bytes = await info.readBytes();

    return FileExportService.saveBytes(
      bytes: bytes,
      fileName: fileName,
      dialogTitle: 'Save Payment Proof',
      type: fp.FileType.custom,
      allowedExtensions: [safeExt],
    );
  }
}
