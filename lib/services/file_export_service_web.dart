import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/services/file_export_service_common.dart';

/// Web implementation of [FileExportService].
///
/// Web cannot present a native save dialog, so the browser triggers a download
/// with an anchor element and a correctly typed [Blob].
class FileExportService {
  static const _defaultMime = 'application/octet-stream';

  /// Triggers a browser download of [bytes] as [fileName].
  ///
  /// [mimeType] is used for the Blob when known; otherwise the extension is
  /// mapped to a MIME type, falling back to `application/octet-stream`.
  ///
  /// Returns [fileName] on success (the browser does not expose the saved
  /// path), or `null` if the operation fails.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String dialogTitle = 'Save File',
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    String? mimeType,
  }) async {
    try {
      final extension = FileExportCommon.primaryExtension(fileName, allowedExtensions);
      final safeFileName = FileExportCommon.ensureExtension(fileName, extension);

      final detected = FileType.fromExtension(safeFileName);
      final effectiveMime = mimeType ??
          detected?.mime ??
          (allowedExtensions != null && allowedExtensions.isNotEmpty
              ? _mimeForExtension(allowedExtensions.first)
              : null) ??
          _defaultMime;

      final data = bytes.buffer.toJS;
      final blobParts = [data].toJS as JSArray<web.BlobPart>;
      final blob = web.Blob(
        blobParts,
        web.BlobPropertyBag(type: effectiveMime),
      );

      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = p.basename(safeFileName);

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);

      return safeFileName;
    } catch (e) {
      return null;
    }
  }

  static String? _mimeForExtension(String ext) {
    final clean = ext.replaceAll('.', '').toLowerCase();
    if (clean == 'jpg' || clean == 'jpeg' || clean == 'jpe' || clean == 'jfif') {
      return 'image/jpeg';
    }
    if (clean == 'png') return 'image/png';
    if (clean == 'webp') return 'image/webp';
    if (clean == 'gif') return 'image/gif';
    if (clean == 'bmp') return 'image/bmp';
    if (clean == 'tiff' || clean == 'tif') return 'image/tiff';
    if (clean == 'heic' || clean == 'heif') return 'image/heic';
    if (clean == 'avif') return 'image/avif';
    if (clean == 'svg') return 'image/svg+xml';
    if (clean == 'pdf') return 'application/pdf';
    if (clean == 'csv') return 'text/csv';
    if (clean == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (clean == 'xls') return 'application/vnd.ms-excel';
    return null;
  }
}
