import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pinoy_pos/core/file_type_utils.dart';

/// Result of a generic file pick/store operation.
class FilePickResult {
  final String? filePath;
  final String? fileName;
  final String? mimeType;
  final String? extension;
  final String? error;

  bool get isSuccess => filePath != null && error == null;

  FilePickResult.success(
    this.filePath, {
    this.fileName,
    this.mimeType,
    this.extension,
  }) : error = null;

  FilePickResult.failure(this.error)
      : filePath = null,
        fileName = null,
        mimeType = null,
        extension = null;
}

/// Generic file storage service for non-image attachments such as PDFs,
/// manuals, and specification sheets.
///
/// Images should continue to use [ImageService], which resizes and stores
/// with image-specific settings. This service is responsible for validation,
/// storage, and cleanup of arbitrary files.
class FileStorageService {
  static const int _defaultMaxSizeBytes = 10 * 1024 * 1024; // 10 MB

  /// Picks a file from the platform file picker and stores it under
  /// [directory] with a safe internally-generated filename.
  ///
  /// Returns the relative path from the app documents directory, plus the
  /// detected MIME type and canonical extension.
  Future<FilePickResult> pickAndStoreFile({
    String directory = 'attachments',
    List<String>? allowedExtensions,
    int maxSizeBytes = _defaultMaxSizeBytes,
  }) async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return FilePickResult.failure('No file selected');
      }

      final platformFile = result.files.first;
      final rawName = platformFile.name;
      final bytes = platformFile.bytes;
      final sourcePath = platformFile.path;

      if (bytes != null && bytes.length > maxSizeBytes) {
        return FilePickResult.failure(
          'File is too large. Maximum size is ${maxSizeBytes ~/ (1024 * 1024)} MB.',
        );
      }

      final fileType = FileTypeUtils.detectFromNameAndBytes(rawName, bytes);
      if (fileType == null) {
        return FilePickResult.failure(
          'Unsupported file format. Please use a supported file type.',
        );
      }

      final canonicalExtension = fileType.extension;
      final baseName = p.basenameWithoutExtension(rawName);
      final safeBaseName = _safeBaseName(baseName);
      final fileName = '$safeBaseName.$canonicalExtension';

      final storedPath = await storeFile(
        bytes: bytes,
        sourcePath: sourcePath,
        directory: directory,
        fileName: fileName,
      );

      if (storedPath == null) {
        return FilePickResult.failure('Failed to save file. Please try again.');
      }

      return FilePickResult.success(
        storedPath,
        fileName: fileName,
        mimeType: fileType.mime,
        extension: canonicalExtension,
      );
    } catch (e) {
      return FilePickResult.failure('Failed to pick file: $e');
    }
  }

  /// Stores [bytes] or the file at [sourcePath] under [directory]/[fileName].
  ///
  /// Exactly one of [bytes] or [sourcePath] should be provided.
  /// Returns the relative path from the app documents directory.
  Future<String?> storeFile({
    Uint8List? bytes,
    String? sourcePath,
    required String directory,
    required String fileName,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(appDir.path, directory));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final destPath = p.join(targetDir.path, fileName);

      if (bytes != null) {
        await File(destPath).writeAsBytes(bytes);
      } else if (sourcePath != null && sourcePath.isNotEmpty && !kIsWeb) {
        await File(sourcePath).copy(destPath);
      } else {
        return null;
      }

      return p.relative(destPath, from: appDir.path);
    } catch (e) {
      return null;
    }
  }

  /// Resolves a stored relative path to an absolute [File].
  ///
  /// Returns null when the path is empty or the file does not exist.
  Future<File?> resolveFile(String? relativePath) async {
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

  /// Deletes the file at the given relative path if it exists.
  ///
  /// Missing files are ignored so callers can safely clean up best-effort.
  Future<void> deleteFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;

    try {
      final file = await resolveFile(relativePath);
      if (file != null) {
        await file.delete();
      }
    } catch (e) {
      // Best-effort cleanup; don't throw if the file is already gone.
    }
  }

  /// Deletes every file in [relativePaths] best-effort.
  Future<void> deleteFiles(List<String> relativePaths) async {
    for (final path in relativePaths) {
      await deleteFile(path);
    }
  }

  /// Returns the size in bytes of the file at [relativePath], or 0 if it
  /// cannot be resolved.
  Future<int> getFileSize(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return 0;
    try {
      final file = await resolveFile(relativePath);
      if (file == null) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  String _safeBaseName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? const Uuid().v4() : cleaned;
  }
}
