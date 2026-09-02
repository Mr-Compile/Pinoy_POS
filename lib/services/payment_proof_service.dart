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

  /// Presents a save dialog for the GCash payment proof and writes it as an
  /// image in its original format.
  ///
  /// The filename is `gcash_proof_sale_<saleId>_<timestamp>.<actualExt>`
  /// (e.g. `gcash_proof_sale_10245_20260902_143522.jpg`). The exported bytes
  /// are the original image contents; the extension is derived from the
  /// detected image type, never from a generic export pipeline.
  ///
  /// Returns the saved path or filename, or `null` if the user cancels or the
  /// file cannot be read.
  Future<String?> exportGcashProofAsImage(Sale sale) async {
    return exportGcashProofAsImageFromPath(sale.paymentProofPath, sale.id);
  }

  /// Exports a GCash payment proof image given its relative [path] and
  /// optional [saleId].
  Future<String?> exportGcashProofAsImageFromPath(
    String? path,
    int? saleId,
  ) async {
    final info = await resolveProofFromPath(path);
    if (info == null) return null;

    final ext = resolveImageExtension(info);
    final mime = info.fileType?.mime ?? FileTypeUtils.mimeForExtension(ext) ?? 'image/jpeg';
    final timestamp = _formatTimestamp(DateTime.now());
    final idSuffix = saleId != null ? '_sale_$saleId' : '';
    final fileName = 'gcash_proof${idSuffix}_$timestamp.$ext';

    final bytes = await info.readBytes();

    return FileExportService.saveBytes(
      bytes: bytes,
      fileName: fileName,
      dialogTitle: 'Download GCash Proof Image',
      type: fp.FileType.image,
      allowedExtensions: [ext],
      mimeType: mime,
    );
  }

  /// Returns the canonical image extension for [info].
  ///
  /// GCash proofs are always images, so the final fallback is `.jpg` rather
  /// than `.bin` or a generic type. If a better image type can be derived from
  /// the original filename or from the actual file bytes, that is used first.
  static String resolveImageExtension(PaymentProofInfo info) {
    if (info.fileType?.isImage == true) {
      return info.fileType!.extension;
    }

    final fromName = p.extension(info.originalName ?? '').replaceAll('.', '');
    final fileType = FileType.fromExtension(fromName);
    if (fileType?.isImage == true) {
      return fileType!.extension;
    }

    // GCash payment proof is an image by definition; a `.jpg` fallback is
    // safer for the user than an extensionless or `.bin` file. The bytes are
    // not converted; only the filename gets the most common image extension.
    return 'jpg';
  }

  /// Formats a timestamp for a filesystem-safe filename.
  static String _formatTimestamp(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '$year$month${day}_$hour$minute${second}_$ms';
  }
}
