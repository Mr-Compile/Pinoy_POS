import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A detected file type with canonical MIME, extension, and human label.
class FileType {
  final String mime;
  final String extension;
  final String label;

  const FileType({
    required this.mime,
    required this.extension,
    required this.label,
  });

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  static const FileType jpeg = FileType(
    mime: 'image/jpeg',
    extension: 'jpg',
    label: 'JPEG Image',
  );

  static const FileType png = FileType(
    mime: 'image/png',
    extension: 'png',
    label: 'PNG Image',
  );

  static const FileType webp = FileType(
    mime: 'image/webp',
    extension: 'webp',
    label: 'WebP Image',
  );

  static const FileType pdf = FileType(
    mime: 'application/pdf',
    extension: 'pdf',
    label: 'PDF Document',
  );

  static const List<FileType> knownTypes = [jpeg, png, webp, pdf];

  static FileType? fromMime(String? mime) {
    if (mime == null) return null;
    final lower = mime.toLowerCase().trim();
    for (final type in knownTypes) {
      if (type.mime == lower) return type;
    }
    return null;
  }

  static FileType? fromExtension(String? extension) {
    if (extension == null) return null;
    final ext = p.extension(extension).toLowerCase().replaceAll('.', '');
    for (final type in knownTypes) {
      if (type.extension == ext) return type;
    }
    return null;
  }

  @override
  String toString() => 'FileType($mime, .$extension, $label)';
}

/// Centralised file-type detection for payment proofs and other files.
///
/// Determines the actual type using file signatures (magic bytes) first,
/// then falls back to the filename extension. The returned [FileType] always
/// carries the canonical MIME and extension for the detected format.
class FileTypeUtils {
  FileTypeUtils._();

  // Magic-byte signatures.
  static const List<int> _jpegSignature = [0xFF, 0xD8, 0xFF];
  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ];
  static const List<int> _riffSignature = [0x52, 0x49, 0x46, 0x46];
  static const List<int> _pdfSignature = [0x25, 0x50, 0x44, 0x46, 0x2D];

  /// Detects the file type from the first bytes of a file.
  ///
  /// Returns `null` when the bytes do not match a known signature and
  /// [fileName] is `null` or has no recognised extension.
  static FileType? detect(
    Uint8List bytes, {
    String? fileName,
  }) {
    final fromBytes = _detectFromBytes(bytes);
    if (fromBytes != null) return fromBytes;

    if (fileName != null && fileName.isNotEmpty) {
      return FileType.fromExtension(fileName);
    }

    return null;
  }

  /// Detects the file type from a filename and optional bytes.
  ///
  /// Magic bytes take precedence over the extension when both are provided.
  static FileType? detectFromNameAndBytes(
    String? fileName,
    Uint8List? bytes,
  ) {
    if (bytes != null && bytes.isNotEmpty) {
      final fromBytes = _detectFromBytes(bytes);
      if (fromBytes != null) return fromBytes;
    }

    if (fileName != null && fileName.isNotEmpty) {
      return FileType.fromExtension(fileName);
    }

    return null;
  }

  static FileType? _detectFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    if (_matchesSignature(bytes, _jpegSignature)) {
      return FileType.jpeg;
    }

    if (_matchesSignature(bytes, _pngSignature)) {
      return FileType.png;
    }

    if (bytes.length >= 12 && _matchesSignature(bytes, _riffSignature)) {
      final fourCC = String.fromCharCodes(bytes.sublist(8, 12));
      if (fourCC == 'WEBP') {
        return FileType.webp;
      }
    }

    if (_matchesSignature(bytes, _pdfSignature)) {
      return FileType.pdf;
    }

    return null;
  }

  static bool _matchesSignature(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  /// Canonical extension for a MIME type, or `null` if unknown.
  static String? extensionForMime(String? mime) =>
      FileType.fromMime(mime)?.extension;

  /// Canonical MIME type for an extension, or `null` if unknown.
  static String? mimeForExtension(String? extension) =>
      FileType.fromExtension(extension)?.mime;

  /// Whether the MIME type is a supported image type.
  static bool isImage(String? mime) =>
      mime != null && mime.toLowerCase().startsWith('image/');

  /// Whether the MIME type is a supported PDF type.
  static bool isPdf(String? mime) =>
      mime != null && mime.toLowerCase() == 'application/pdf';
}
