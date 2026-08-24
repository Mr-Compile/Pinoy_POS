import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:pinoy_pos/data/models/backup_location.dart';

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
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Backup Location',
      initialDirectory: initial?.reference,
    );
    if (path == null || path.isEmpty) return null;

    final displayName = _displayNameFromPath(path);
    if (!await _isDirectoryWritable(path)) {
      throw BackupStorageException('The selected folder cannot be written to.');
    }

    return BackupLocation(
      type: BackupStorageType.fileSystem,
      reference: path,
      displayName: displayName,
    );
  }

  /// Picks a backup file for restore and returns its bytes.
  ///
  /// Uses [FilePicker] on all platforms. On Android the chosen file is
  /// copied to a temporary file so SQLite validation can open it by path.
  /// The returned [BackupReadResult.bytes] are the raw backup bytes.
  Future<BackupReadResult> pickBackupForRestore() async {
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
    if (Platform.isAndroid) {
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

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'createDocument',
        {
          'treeUri': location.reference,
          'displayName': _makeUniqueFileName(defaultFileName),
          'mimeType': 'application/x-sqlite3',
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
      final picked = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (picked == null || picked.isEmpty) {
        return const BackupWriteResult(success: false, error: null);
      }
      targetPath = _ensureDbExtension(picked);
      displayName = p.basename(targetPath);
      writtenTo = BackupLocation(
        type: BackupStorageType.fileSystem,
        reference: p.dirname(targetPath),
        displayName: _displayNameFromPath(p.dirname(targetPath)),
      );
    } else {
      targetPath = p.join(
        location.reference,
        _makeUniqueFileName(defaultFileName, existingDir: Directory(location.reference)),
      );
    }

    try {
      final file = File(targetPath);
      await file.writeAsBytes(bytes, flush: true);
      final fileSize = await file.length();

      return BackupWriteResult(
        success: true,
        storageReference: targetPath,
        displayName: displayName,
        fileSize: fileSize,
        writtenTo: writtenTo,
      );
    } catch (e) {
      return BackupWriteResult(
        success: false,
        error: 'Could not write the backup file: $e',
      );
    }
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
    try {
      final file = File(reference);
      if (!await file.exists()) {
        return const BackupReadResult(
          success: false,
          error: 'The backup file was not found at the saved location.',
        );
      }
      final bytes = await file.readAsBytes();
      return BackupReadResult(
        success: true,
        displayName: p.basename(reference),
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
      return _isDirectoryWritable(location.reference);
    }

    return false;
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
    return p.basename(reference);
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

    try {
      final file = File(reference);
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
    final parts = p.split(path);
    if (parts.isEmpty) return path;
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

  String _ensureDbExtension(String path) {
    if (!path.toLowerCase().endsWith('.db')) return '$path.db';
    return path;
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

  Future<bool> _isDirectoryWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      final probe = File(p.join(path, '.pinoy_pos_probe'));
      await probe.writeAsString('probe', flush: true);
      await probe.delete();
      return true;
    } catch (e) {
      return false;
    }
  }
}

class BackupStorageException implements Exception {
  final String message;
  BackupStorageException(this.message);

  @override
  String toString() => message;
}
