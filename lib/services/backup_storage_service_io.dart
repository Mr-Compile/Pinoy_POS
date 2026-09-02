import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pinoy_pos/data/models/backup_location.dart';
import 'package:pinoy_pos/services/file_export_service.dart';

/// Platform-specific backup storage implementation for Android, iOS,
/// Windows, Linux, and macOS.
///
/// On Android it uses a custom MethodChannel that talks to the Android
/// Storage Access Framework (SAF) so the user can pick a folder once and
/// the app can create and read backups in that folder across restarts.
///
/// On Windows / desktop it uses [FilePicker] to select a folder and plain
/// Dart [File] operations to write the backup.
class BackupStorageService {
  static const _channel = MethodChannel('com.pinoypos.pinoy_pos/backup_storage');

  /// Picks a backup destination folder.
  ///
  /// On Android this launches [ACTION_OPEN_DOCUMENT_TREE] and persists the
  /// grant. On desktop it launches the native folder picker.
  /// Returns null when the user cancels.
  Future<BackupLocation?> pickLocation({BackupLocation? initial}) async {
    if (Platform.isAndroid) {
      try {
        final initialUri = initial?.type == BackupStorageType.androidSaf
            ? initial!.reference
            : null;
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'openDocumentTree',
          {'initialUri': initialUri},
        );
        if (result == null) return null;
        final uri = result['uri'] as String?;
        final displayName = result['displayName'] as String?;
        if (uri == null || uri.isEmpty) return null;
        return BackupLocation(
          type: BackupStorageType.androidSaf,
          reference: uri,
          displayName: displayName ?? _displayNameFromUri(uri),
        );
      } on PlatformException catch (e) {
        throw BackupStorageException('Failed to open folder picker: ${e.message}');
      }
    }

    // Desktop fallback (Windows / Linux / macOS).
    final initialDirectory = initial != null && initial.type == BackupStorageType.fileSystem
        ? _toFilesystemPath(initial.reference)
        : null;

    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Backup Location',
      initialDirectory: initialDirectory,
    );
    if (picked == null || picked.isEmpty) return null;

    final displayName = _displayNameFromPath(picked);
    final (writable, error) = await _isDirectoryWritable(picked);
    if (!writable) {
      throw BackupStorageException(
        'The selected folder cannot be written to. ${error ?? 'Please choose a different folder.'}',
      );
    }

    return BackupLocation(
      type: BackupStorageType.fileSystem,
      reference: picked,
      displayName: displayName,
    );
  }

  /// Picks a backup file for restore and returns its bytes.
  ///
  /// On Android this launches a Storage Access Framework picker so the
  /// user can choose any file (including `.db` files that the regular
  /// file picker cannot filter for). On desktop it uses [FilePicker].
  /// The returned [BackupReadResult.bytes] are the raw backup bytes.
  Future<BackupReadResult> pickBackupForRestore() async {
    if (Platform.isAndroid) {
      return _pickBackupForRestoreAndroid();
    }

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Backup',
      type: FileType.custom,
      allowedExtensions: ['db'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return const BackupReadResult(
        success: false,
        error: null,
        bytes: null,
        displayName: null,
        fileSize: null,
      );
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const BackupReadResult(
        success: false,
        error: 'The selected backup file is empty.',
      );
    }

    return BackupReadResult(
      success: true,
      displayName: file.name,
      fileSize: bytes.length,
      bytes: bytes,
    );
  }

  Future<BackupReadResult> _pickBackupForRestoreAndroid() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'openDocument',
        {
          // Use a broad filter: Android's MIME mapping does not reliably
          // recognise .db files, so a restrictive filter hides backups.
          // The file is validated by its SQLite header after selection.
          'mimeTypes': ['*/*'],
        },
      );

      if (result == null) {
        return const BackupReadResult(
          success: false,
          error: null,
          bytes: null,
          displayName: null,
          fileSize: null,
        );
      }

      final rawBytes = result['bytes'];
      final bytes = rawBytes is Uint8List
          ? rawBytes
          : rawBytes is List<int>
              ? Uint8List.fromList(rawBytes)
              : null;

      if (bytes == null || bytes.isEmpty) {
        return const BackupReadResult(
          success: false,
          error: 'The selected backup file is empty.',
        );
      }

      return BackupReadResult(
        success: true,
        displayName: result['displayName'] as String?,
        fileSize: result['size'] as int? ?? bytes.length,
        bytes: bytes,
      );
    } on PlatformException catch (e) {
      return BackupReadResult(
        success: false,
        error: 'Failed to read backup: ${e.message}',
      );
    }
  }

  /// Writes a backup to the given [location].
  ///
  /// On Android [location] must be an SAF tree URI; the file is created as
  /// a child of that tree. On desktop [location] is a file-system path.
  ///
  /// When [location] is null the user is asked to choose a destination each
  /// time (desktop save-as dialog or Android create-document dialog).
  ///
  /// The returned [BackupWriteResult] carries the [storageReference] needed
  /// to identify the file later (path or content URI).
  Future<BackupWriteResult> saveBackup({
    required Uint8List bytes,
    required String defaultFileName,
    BackupLocation? location,
    BackupLocation? defaultLocation,
  }) async {
    // Reject a persisted location whose reference no longer matches its type
    // (e.g. a v1 path that was actually a content URI or a web URL).
    if (location != null && !location.isReferenceValidForType) {
      location = null;
    }

    if (Platform.isAndroid) {
      // A persisted fileSystem location on Android (e.g. from a v1 migration)
      // cannot be used with the SAF createDocument channel.  If the directory
      // is still writable, write through the desktop file path logic; otherwise
      // force the user to pick a proper SAF folder.
      if (location != null && location.type == BackupStorageType.fileSystem) {
        final (writable, _) = await _isDirectoryWritable(location.reference);
        if (!writable) {
          location = null;
        } else {
          return _saveBackupDesktop(
            bytes: bytes,
            defaultFileName: defaultFileName,
            location: location,
          );
        }
      }

      return _saveBackupAndroid(
        bytes: bytes,
        defaultFileName: defaultFileName,
        location: location,
      );
    }

    return _saveBackupDesktop(
      bytes: bytes,
      defaultFileName: defaultFileName,
      location: location,
    );
  }

  Future<BackupWriteResult> _saveBackupAndroid({
    required Uint8List bytes,
    required String defaultFileName,
    BackupLocation? location,
  }) async {
    if (location == null || location.isNone) {
      // No default location: ask the user to pick a folder and create the
      // file there.
      final picked = await pickLocation();
      if (picked == null) {
        return const BackupWriteResult(
          success: false,
          error: null,
        );
      }
      location = picked;
    }

    if (!location.isReferenceValidForType) {
      return const BackupWriteResult(
        success: false,
        error: 'The selected backup location is not a valid SAF folder.',
      );
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'createDocument',
        {
          'treeUri': location.reference,
          'displayName': _makeUniqueFileName(defaultFileName),
          // Use a generic MIME type: some document providers reject
          // application/x-sqlite3, while application/octet-stream is
          // accepted by all providers and the .db extension is preserved
          // in the display name.
          'mimeType': 'application/octet-stream',
          'bytes': bytes,
        },
      );

      if (result == null) {
        return const BackupWriteResult(
          success: false,
          error: 'Could not create the backup file in the selected folder.',
        );
      }

      final uri = result['uri'] as String?;
      final displayName = result['displayName'] as String? ?? defaultFileName;
      final fileSize = result['size'] as int? ?? bytes.length;

      if (uri == null || uri.isEmpty) {
        return const BackupWriteResult(
          success: false,
          error: 'The backup file was not created.',
        );
      }

      if (fileSize == 0) {
        return const BackupWriteResult(
          success: false,
          error: 'The backup file was empty after writing.',
        );
      }

      return BackupWriteResult(
        success: true,
        storageReference: uri,
        displayName: displayName,
        fileSize: fileSize,
        writtenTo: location,
      );
    } on PlatformException catch (e) {
      return BackupWriteResult(
        success: false,
        error: 'Failed to write backup: ${e.message}',
      );
    }
  }

  Future<BackupWriteResult> _saveBackupDesktop({
    required Uint8List bytes,
    required String defaultFileName,
    BackupLocation? location,
  }) async {
    String? targetPath;
    String displayName = defaultFileName;
    BackupLocation? writtenTo = location;

    if (location == null || location.isNone) {
      // No default location: open a save-as dialog.
      targetPath = await FileExportService.saveBytes(
        bytes: bytes,
        fileName: defaultFileName,
        dialogTitle: 'Export Backup',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (targetPath == null || targetPath.isEmpty) {
        return const BackupWriteResult(success: false, error: null);
      }

      final path = _toFilesystemPath(targetPath);
      if (path == null) {
        return const BackupWriteResult(
          success: false,
          error: 'The chosen save location is not a valid file path.',
        );
      }
      targetPath = path;

      displayName = p.basename(targetPath);
      writtenTo = BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: p.dirname(targetPath),
        displayName: _displayNameFromPath(p.dirname(targetPath)),
      );
    } else {
      final path = _toFilesystemPath(location.reference);
      if (path == null) {
        return const BackupWriteResult(
          success: false,
          error: 'The selected location is not a valid folder path.',
        );
      }

      targetPath = p.join(
        path,
        _makeUniqueFileName(defaultFileName, existingDir: Directory(path)),
      );

      try {
        final file = File(targetPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);

        // Verify the file was actually written and is non-empty.
        if (!await file.exists() || await file.length() == 0) {
          return const BackupWriteResult(
            success: false,
            error: 'The backup file could not be verified after writing.',
          );
        }
      } catch (e) {
        return BackupWriteResult(
          success: false,
          error: 'Could not write the backup file: $e',
        );
      }
    }

    final fileSize = await _safeFileSize(targetPath, fallback: bytes.length);

    return BackupWriteResult(
      success: true,
      storageReference: targetPath,
      displayName: displayName,
      fileSize: fileSize,
      writtenTo: writtenTo,
    );
  }

  Future<int> _safeFileSize(String path, {required int fallback}) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return fallback;
  }

  /// Reads a backup from a saved [reference] (path or URI).
  ///
  /// Used by "Restore from history" where the user does not pick the file
  /// again.
  Future<BackupReadResult> readBackup(String reference) async {
    if (Platform.isAndroid && _isContentUri(reference)) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'readDocument',
          {'uri': reference},
        );
        if (result == null) {
          return const BackupReadResult(
            success: false,
            error: 'The backup file is no longer accessible.',
          );
        }
        final bytes = result['bytes'] as Uint8List?;
        if (bytes == null || bytes.isEmpty) {
          return const BackupReadResult(
            success: false,
            error: 'The backup file is empty.',
          );
        }
        return BackupReadResult(
          success: true,
          displayName: result['displayName'] as String?,
          fileSize: result['size'] as int? ?? bytes.length,
          bytes: bytes,
        );
      } on PlatformException catch (e) {
        return BackupReadResult(
          success: false,
          error: 'Failed to read backup: ${e.message}',
        );
      }
    }

    // Desktop / file-system path.
    final path = _toFilesystemPath(reference);
    if (path == null) {
      return const BackupReadResult(
        success: false,
        error: 'The saved backup reference is not a valid file path.',
      );
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        return const BackupReadResult(
          success: false,
          error: 'The backup file was not found at the saved location.',
        );
      }
      final bytes = await file.readAsBytes();
      return BackupReadResult(
        success: true,
        displayName: p.basename(path),
        fileSize: bytes.length,
        bytes: bytes,
      );
    } catch (e) {
      return BackupReadResult(
        success: false,
        error: 'Failed to read backup: $e',
      );
    }
  }

  /// Verifies the saved backup location is still accessible.
  Future<bool> isLocationValid(BackupLocation location) async {
    if (location.isNone) return false;
    if (!location.isReferenceValidForType) return false;

    if (location.type == BackupStorageType.androidSaf) {
      try {
        final valid = await _channel.invokeMethod<bool>(
          'isUriValid',
          {'uri': location.reference},
        );
        return valid == true;
      } catch (e) {
        return false;
      }
    }

    if (location.type == BackupStorageType.fileSystem) {
      final path = _toFilesystemPath(location.reference);
      if (path == null) return false;

      if (Platform.isAndroid) {
        // On Android a non-SAF path is rarely persistently writable across
        // sessions and should not count as a valid backup location.
        final (writable, _) = await _isDirectoryWritable(path);
        return writable;
      }
      final (valid, _) = await _isDirectoryWritable(path);
      return valid;
    }

    return false;
  }

  /// Returns a default, writable backup folder on desktop.
  ///
  /// Uses `Documents/Pinoy POS Backups`. Creates the folder and verifies it
  /// can be written before returning it. Returns null on unsupported platforms
  /// or if the folder is not writable.
  Future<BackupLocation?> getDefaultDesktopLocation() async {
    if (Platform.isAndroid) return null;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final path = p.join(docs.path, 'Pinoy POS Backups');
      final dir = Directory(path);
      await dir.create(recursive: true);

      final (writable, error) = await _isDirectoryWritable(path);
      if (!writable) {
        debugPrint('[BackupStorageService] Default backup location not writable: $error');
        return null;
      }

      return BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: path,
        displayName: _displayNameFromPath(path),
      );
    } catch (e) {
      debugPrint('[BackupStorageService] Could not create default backup location: $e');
      return null;
    }
  }

  /// Returns a human-readable label for a saved storage reference.
  Future<String> getDisplayName(String reference) async {
    if (Platform.isAndroid && _isContentUri(reference)) {
      try {
        final name = await _channel.invokeMethod<String>(
          'getDisplayName',
          {'uri': reference},
        );
        return name ?? _displayNameFromUri(reference);
      } catch (e) {
        return _displayNameFromUri(reference);
      }
    }
    final path = _toFilesystemPath(reference) ?? reference;
    return p.basename(path);
  }

  /// Returns a human-readable label for a backup location folder.
  String getLocationDisplayName(BackupLocation location) {
    if (location.isNone) return '';
    if (location.displayName.isNotEmpty) return location.displayName;
    if (location.type == BackupStorageType.androidSaf) {
      return _displayNameFromUri(location.reference);
    }
    return _displayNameFromPath(location.reference);
  }

  /// Deletes a backup file by its storage reference.
  Future<bool> deleteBackup(String reference) async {
    if (Platform.isAndroid && _isContentUri(reference)) {
      try {
        final deleted = await _channel.invokeMethod<bool>(
          'deleteDocument',
          {'uri': reference},
        );
        return deleted == true;
      } catch (e) {
        return false;
      }
    }

    final path = _toFilesystemPath(reference);
    if (path == null) return false;

    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Releases a persisted SAF grant for the given URI.
  Future<void> releaseUri(String reference) async {
    if (Platform.isAndroid && _isContentUri(reference)) {
      try {
        await _channel.invokeMethod('releaseUri', {'uri': reference});
      } catch (e) {
        debugPrint('[BackupStorageService] releaseUri failed: $e');
      }
    }
  }

  String _displayNameFromPath(String path) {
    final resolved = _decodeFileUri(path);
    final parts = p.split(resolved);
    if (parts.isEmpty) return resolved;
    if (parts.length <= 3) return parts.join(' › ');
    return '... › ${parts.sublist(parts.length - 3).join(' › ')}';
  }

  String _displayNameFromUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return 'Selected folder';
      if (segments.length <= 3) return segments.join(' › ');
      return '... › ${segments.sublist(segments.length - 3).join(' › ')}';
    } catch (e) {
      return 'Selected folder';
    }
  }

  bool _isContentUri(String reference) {
    return reference.startsWith('content://');
  }

  bool _isFileUri(String reference) {
    return reference.startsWith('file://');
  }

  /// Decodes a `file://` URI to a filesystem path. Returns the original
  /// string unchanged if it cannot be decoded.
  String _decodeFileUri(String reference) {
    if (!_isFileUri(reference)) return reference;
    try {
      final uri = Uri.parse(reference);
      if (uri.scheme == 'file') return uri.toFilePath();
    } catch (e) {
      debugPrint('[BackupStorageService] Could not decode file URI: $reference');
    }
    return reference;
  }

  /// Throws if [path] looks like a URI rather than a local filesystem path.
  void _assertFilesystemPath(String path) {
    if (path.trim().contains('://')) {
      throw BackupStorageException(
        'Refusing to use a URI as a local path: $path',
      );
    }
  }

  /// Returns [reference] as a local path, decoding `file://` if present.
  ///
  /// Returns `null` if the reference is neither a path nor a decodable
  /// `file://` URI, so callers can fail with a clear message instead of
  /// passing a URL to Dart [File] APIs.
  String? _toFilesystemPath(String reference) {
    if (!reference.contains('://')) return reference;
    if (_isFileUri(reference)) return _decodeFileUri(reference);
    return null;
  }

  String _makeUniqueFileName(String baseName, {Directory? existingDir}) {
    if (existingDir == null || !existingDir.existsSync()) return baseName;

    final name = p.basenameWithoutExtension(baseName);
    final ext = p.extension(baseName);
    var candidate = baseName;
    for (var i = 1; i < 100; i++) {
      final file = File(p.join(existingDir.path, candidate));
      if (!file.existsSync()) return candidate;
      candidate = '${name}_$i$ext';
    }
    return '${name}_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  Future<(bool, String?)> _isDirectoryWritable(String reference) async {
    final path = _toFilesystemPath(reference);
    if (path == null) {
      return (false, 'The selected reference is not a valid folder path.');
    }

    _assertFilesystemPath(path);

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return (false, 'The folder does not exist.');
      }
      final probe = File(p.join(path, '.pinoy_pos_probe'));
      await probe.writeAsString('probe', flush: true);
      await probe.delete();
      return (true, null);
    } on FileSystemException catch (e) {
      return (false, 'File system error: ${e.message}');
    } catch (e) {
      return (false, e.toString());
    }
  }
}

class BackupStorageException implements Exception {
  final String message;
  BackupStorageException(this.message);

  @override
  String toString() => message;
}
