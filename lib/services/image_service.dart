import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Result of an image pick operation.
///
/// Carries either a valid [filePath] pointing to the stored image or an
/// [error] message describing why the pick failed.  The UI layer uses this
/// to show a dialog (never a SnackBar) on failure.
class ImagePickResult {
  final String? filePath;
  final String? error;

  bool get isSuccess => filePath != null && error == null;

  ImagePickResult.success(this.filePath)
      : error = null;

  ImagePickResult.failure(this.error)
      : filePath = null;
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

  static const List<String> _allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

  /// Picks an image from the gallery, validates it, copies it into
  /// app-controlled storage, and returns the relative path.
  ///
  /// Returns [ImagePickResult.failure] with a user-friendly message if
  /// the user cancels, the file is too large, the extension is not
  /// supported, or the file cannot be read.
  Future<ImagePickResult> pickAndStoreImage({
    ImageSource source = ImageSource.gallery,
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

      // Validate extension
      final extension = p.extension(xFile.name).toLowerCase();
      if (!_allowedExtensions.contains(extension)) {
        return ImagePickResult.failure(
          'Unsupported file format. Please use JPG, PNG, or WebP.',
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

      // Store the image in app-controlled directory
      final storedPath = await _storeImage(xFile, extension);
      if (storedPath == null) {
        return ImagePickResult.failure('Failed to save image. Please try again.');
      }

      return ImagePickResult.success(storedPath);
    } catch (e) {
      return ImagePickResult.failure('Failed to pick image: $e');
    }
  }

  /// Stores the picked image in the app documents directory under
  /// `images/` with a UUID-based filename.  Returns the **relative** path
  /// from the app documents directory, or null on failure.
  Future<String?> _storeImage(XFile xFile, String extension) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(appDir.path, 'images'));

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final filename = '${const Uuid().v4()}$extension';
      final destPath = p.join(imagesDir.path, filename);

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
