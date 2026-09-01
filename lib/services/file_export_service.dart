import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Cross-platform helper for saving byte data through a native save dialog.
///
/// On Android and iOS, [file_picker]'s `saveFile` requires the bytes up front
/// and writes the file itself. On desktop (Windows, macOS, Linux) the picker
/// only returns a path, so the bytes are written with [File].
class FileExportService {
  /// Presents a save-file dialog and writes [bytes] to the selected location.
  ///
  /// Returns the saved file path, or `null` if the user cancels. Returns `null`
  /// on web because the legacy [FilePicker.platform.saveFile] API is not
  /// supported there.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String dialogTitle = 'Save File',
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (kIsWeb) return null;

    final isMobile = Platform.isAndroid || Platform.isIOS;

    final picked = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: isMobile ? bytes : null,
    );

    if (picked == null || picked.isEmpty) return null;

    final extension = _primaryExtension(fileName, allowedExtensions);
    final path = _ensureExtension(picked, extension);

    if (!isMobile) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    return path;
  }

  static String _primaryExtension(String fileName, List<String>? allowedExtensions) {
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      return allowedExtensions.first;
    }
    final ext = p.extension(fileName);
    return ext.isEmpty ? '' : ext.substring(1);
  }

  static String _ensureExtension(String path, String extension) {
    if (extension.isEmpty) return path;

    final dotExt = '.$extension';
    if (path.toLowerCase().endsWith(dotExt.toLowerCase())) return path;

    return '$path$dotExt';
  }
}
