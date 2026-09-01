import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:pinoy_pos/services/file_export_service_common.dart';

/// Native (Android, iOS, Windows, macOS, Linux) implementation of
/// [FileExportService].
class FileExportService {
  /// Presents a save-file dialog and writes [bytes] to the selected location.
  ///
  /// Returns the saved file path, or `null` if the user cancels.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String dialogTitle = 'Save File',
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String? mimeType,
  }) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    final picked = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: isMobile ? bytes : null,
    );

    if (picked == null || picked.isEmpty) return null;

    final extension = FileExportCommon.primaryExtension(fileName, allowedExtensions);
    final path = FileExportCommon.ensureExtension(picked, extension);

    if (!isMobile) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    return path;
  }
}
