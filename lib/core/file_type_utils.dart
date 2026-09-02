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

  static const FileType gif = FileType(
    mime: 'image/gif',
    extension: 'gif',
    label: 'GIF Image',
  );

  static const FileType bmp = FileType(
    mime: 'image/bmp',
    extension: 'bmp',
    label: 'BMP Image',
  );

  static const FileType tiff = FileType(
    mime: 'image/tiff',
    extension: 'tiff',
    label: 'TIFF Image',
  );

  static const FileType heic = FileType(
    mime: 'image/heic',
    extension: 'heic',
    label: 'HEIC Image',
  );

  static const FileType avif = FileType(
    mime: 'image/avif',
    extension: 'avif',
    label: 'AVIF Image',
  );

  static const FileType svg = FileType(
    mime: 'image/svg+xml',
    extension: 'svg',
    label: 'SVG Image',
  );

  static const FileType pdf = FileType(
    mime: 'application/pdf',
    extension: 'pdf',
    label: 'PDF Document',
  );

  static const List<FileType> knownTypes = [
    jpeg,
    png,
    webp,
    gif,
    bmp,
    tiff,
    heic,
    avif,
    svg,
    pdf,
  ];

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
    final raw = extension.toLowerCase().trim();
    if (raw.isEmpty) return null;

    // Accept either a bare extension (e.g. 'jpg') or a filename
    // (e.g. 'proof.jpg'). For filenames we extract the extension using
    // path.package; otherwise we use the value directly.
    final ext = raw.contains('.') ? p.extension(raw).replaceAll('.', '') : raw;

    // JPEG has several common extensions; canonicalise them all.
    if (ext == 'jpeg' || ext == 'jpe' || ext == 'jfif') {
      return jpeg;
    }

    // TIFF may use the three-letter form.
    if (ext == 'tif') {
      return tiff;
    }

    // HEIF/HEIC are usually interchangeable in Flutter apps.
    if (ext == 'heif') {
      return heic;
    }

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
  static const List<int> _gifSignature = [0x47, 0x49, 0x46];
  static const List<int> _bmpSignature = [0x42, 0x4D];
  static const List<int> _tiffLittleSignature = [0x49, 0x49, 0x2A, 0x00];
  static const List<int> _tiffBigSignature = [0x4D, 0x4D, 0x00, 0x2A];

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

    if (_matchesSignature(bytes, _gifSignature)) {
      return FileType.gif;
    }

    if (_matchesSignature(bytes, _bmpSignature)) {
      return FileType.bmp;
    }

    if (_matchesSignature(bytes, _tiffLittleSignature) ||
        _matchesSignature(bytes, _tiffBigSignature)) {
      return FileType.tiff;
    }

    if (_matchesSignature(bytes, _pdfSignature)) {
      return FileType.pdf;
    }

    // HEIC/HEIF and AVIF use the ISO Base Media File Format (ISOBMFF).
    // The `ftyp` box starts at offset 4 and the brand follows at offset 8.
    if (bytes.length >= 16) {
      final ftyp = bytes.sublist(4, 8);
      if (_listEquals(ftyp, [0x66, 0x74, 0x79, 0x70])) {
        final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
        if (brand == 'heic' ||
            brand == 'heix' ||
            brand == 'hevc' ||
            brand == 'heim' ||
            brand == 'heis' ||
            brand == 'hevm' ||
            brand == 'hevs' ||
            brand == 'mif1' ||
            brand == 'msf1') {
          return FileType.heic;
        }
        if (brand == 'avif') {
          return FileType.avif;
        }
      }
    }

    // SVG is text-based, so check the start of the file.
    if (_looksLikeSvg(bytes)) {
      return FileType.svg;
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

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _looksLikeSvg(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    try {
      final ascii = String.fromCharCodes(bytes.take(256).toList());
      final trimmed = ascii.trim().toLowerCase();
      return trimmed.startsWith('<?xml') ||
          trimmed.startsWith('<svg') ||
          trimmed.startsWith('<!doctype svg');
    } catch (_) {
      return false;
    }
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
