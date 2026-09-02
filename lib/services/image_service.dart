import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pinoy_pos/core/file_type_utils.dart';

/// Result of an image pick operation.
///
/// Carries either a valid [filePath] pointing to the stored image or an
/// [error] message describing why the pick failed.  The UI layer uses this
/// to show a dialog (never a SnackBar) on failure.
///
/// [mediaType] is the canonical MIME type (e.g. `image/jpeg`) and
/// [extension] is the canonical extension (e.g. `jpg`) detected from the
/// file signature and/or filename.
class ImagePickResult {
  final String? filePath;
  final String? mediaType;
  final String? extension;
  final String? error;

  bool get isSuccess => filePath != null && error == null;

  ImagePickResult.success(
    this.filePath, {
    this.mediaType,
    this.extension,
  }) : error = null;

  ImagePickResult.failure(this.error)
      : filePath = null,
        mediaType = null,
        extension = null;
}

/// Centralised image handling service.
///
/// Responsibilities:
///   - Pick an image from gallery or camera via [ImagePicker]
///   - Validate file existence, extension, and file size
///   - Copy the picked file into app-controlled storage with a safe,
///     internally-generated filename (UUID-based)
///   - Clean up old image files when they are replaced or removed
///
/// The service is offline-first: no network access is required.  Images
/// are stored in the application documents directory under a `images/`
/// subdirectory.
///
/// Stored paths are **relative** to the app documents directory so that
/// they remain valid across app restarts and are not tied to an absolute
/// filesystem path that may change between platforms or installs.
class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final ImagePicker _picker = ImagePicker();
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  /// Picks an image from the gallery, validates it, copies it into
  /// app-controlled storage, and returns the relative path.
  ///
  /// The optional [directory] places the file under a subdirectory of the
  /// application documents folder (e.g. `images` for product photos,
  /// `payment_evidence/tmp` for transient payment proof). When [fileName]
  /// is provided, that name (without extension) is used; otherwise a UUID
  /// is generated.
  ///
  /// Returns [ImagePickResult.failure] with a user-friendly message if
  /// the user cancels, the file is too large, the type is not a supported
  /// image, or the file cannot be read.
  Future<ImagePickResult> pickAndStoreImage({
    ImageSource source = ImageSource.gallery,
    String directory = 'images',
    String? fileName,
    double maxWidth = 1024,
    double maxHeight = 1024,
  }) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: 85,
      );

      if (xFile == null) {
        return ImagePickResult.failure('No image selected');
      }

      // Detect the actual image type from its bytes (and filename as a
      // fallback). This preserves the format even when the source file has
      // no extension or a misleading one.
      final fileType = await _detectType(xFile);
      if (fileType == null || !fileType.isImage) {
        return ImagePickResult.failure(
          'Unsupported file format. Please use a common image such as JPG, PNG, or WebP.',
        );
      }

      // Validate file size (skip on web where xFile.length may behave differently)
      if (!kIsWeb) {
        final file = File(xFile.path);
        if (!await file.exists()) {
          return ImagePickResult.failure('Selected file does not exist');
        }
        final fileSize = await file.length();
        if (fileSize > _maxFileSizeBytes) {
          return ImagePickResult.failure(
            'Image is too large. Maximum size is 5 MB.',
          );
        }
      }

      // Store the image using the canonical extension so the saved file
      // always has a recognised image extension.
      final canonicalExtension = '.${fileType.extension}';
      final storedPath = await _storeImage(
        xFile,
        canonicalExtension,
        directory: directory,
        fileName: fileName,
      );
      if (storedPath == null) {
        return ImagePickResult.failure('Failed to save image. Please try again.');
      }

      return ImagePickResult.success(
        storedPath,
        mediaType: fileType.mime,
        extension: fileType.extension,
      );
    } catch (e) {
      return ImagePickResult.failure('Failed to pick image: $e');
    }
  }

  /// Stores the picked image in the app documents directory under
  /// [directory] with a UUID-based filename unless [fileName] is given.
  ///
  /// [extension] must include the leading dot (e.g. `.jpg`).
  /// Returns the **relative** path from the app documents directory,
  /// or null on failure.
  Future<String?> _storeImage(
    XFile xFile,
    String extension, {
    required String directory,
    String? fileName,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(appDir.path, directory));

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final safeExtension = extension.startsWith('.') ? extension : '.$extension';
      final baseName = fileName ?? const Uuid().v4();
      final filename = '$baseName$safeExtension';
      final destPath = p.join(targetDir.path, filename);

      if (kIsWeb) {
        // On web, read bytes and write to the virtual filesystem
        final bytes = await xFile.readAsBytes();
        await File(destPath).writeAsBytes(bytes);
      } else {
        // On mobile/desktop, copy the file
        final sourceFile = File(xFile.path);
        await sourceFile.copy(destPath);
      }

      // Return relative path from app documents directory
      return p.relative(destPath, from: appDir.path);
    } catch (e) {
      return null;
    }
  }

  /// Detects the actual file type of a picked image using magic bytes and
  /// filename fallback.
  ///
  /// Reads a larger initial chunk so HEIC/AVIF brands and SVG/XML headers are
  /// available for detection.
  Future<FileType?> _detectType(XFile xFile) async {
    try {
      final chunk = await xFile.openRead(0, 512).first;
      final fromBytes = FileTypeUtils.detect(chunk, fileName: xFile.name);
      if (fromBytes != null) return fromBytes;
      return FileType.fromExtension(xFile.name);
    } catch (_) {
      return FileType.fromExtension(xFile.name);
    }
  }

  /// Detects the actual file type of a stored file from its relative path.
  ///
  /// Reads a larger initial chunk so HEIC/AVIF/SVG signatures can be detected
  /// from files that have no extension.
  Future<FileType?> detectFileType(String? relativePath) async {
    final file = await resolveImageFile(relativePath);
    if (file == null) return null;

    try {
      final raf = await file.open();
      final bytes = await raf.read(512);
      await raf.close();
      return FileTypeUtils.detect(bytes, fileName: file.path);
    } catch (_) {
      return FileType.fromExtension(file.path);
    }
  }

  /// Resolves a stored relative path to an absolute [File].
  ///
  /// Returns null if the path is null, empty, or the file does not exist.
  Future<File?> resolveImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final absolutePath = p.join(appDir.path, relativePath);
      final file = File(absolutePath);
      if (await file.exists()) {
        return file;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Moves a stored image from [oldRelativePath] to [newRelativePath]
  /// (both relative to the app documents directory) and returns the new
  /// relative path, or null if the move fails.
  Future<String?> moveImage(String? oldRelativePath, String newRelativePath) async {
    if (oldRelativePath == null || oldRelativePath.isEmpty) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final oldAbsolute = p.join(appDir.path, oldRelativePath);
      final newAbsolute = p.join(appDir.path, newRelativePath);

      final oldFile = File(oldAbsolute);
      if (!await oldFile.exists()) return null;

      final newDir = Directory(p.dirname(newAbsolute));
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      await oldFile.rename(newAbsolute);
      return newRelativePath;
    } catch (e) {
      return null;
    }
  }

  /// Deletes the image file at the given relative path if it exists.
  ///
  /// Called after a new image has been successfully stored and persisted,
  /// or when an image is explicitly removed.  Safe to call with null or
  /// a path that no longer exists.
  Future<void> deleteImage(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;

    try {
      final file = await resolveImageFile(relativePath);
      if (file != null) {
        await file.delete();
      }
    } catch (e) {
      // Best-effort cleanup; don't throw if the file is already gone
    }
  }
}
