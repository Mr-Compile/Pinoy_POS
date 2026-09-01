import 'package:path/path.dart' as p;

/// Shared filename helpers for [FileExportService].
class FileExportCommon {
  FileExportCommon._();

  /// Returns the canonical extension to use for the saved file.
  ///
  /// Prefers the first allowed extension when provided, otherwise extracts
  /// the extension from [fileName]. Returns an empty string when neither is
  /// available.
  static String primaryExtension(
    String fileName,
    List<String>? allowedExtensions,
  ) {
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      return allowedExtensions.first;
    }
    final ext = p.extension(fileName);
    return ext.isEmpty ? '' : ext.substring(1);
  }

  /// Ensures [path] ends with [extension] without double-appending it.
  static String ensureExtension(String path, String extension) {
    if (extension.isEmpty) return path;

    final dotExt = '.$extension';
    if (path.toLowerCase().endsWith(dotExt.toLowerCase())) return path;

    return '$path$dotExt';
  }
}
