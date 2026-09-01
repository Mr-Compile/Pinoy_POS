import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:pinoy_pos/data/models/backup_location.dart';

/// Web implementation of backup storage.
///
/// Web cannot persist arbitrary folders, so the "default location" is not
/// supported. Backups are downloaded through the browser and restores are
/// loaded from a user-picked file.
class BackupStorageService {
  static const _downloadMimeType = 'application/x-sqlite3';

  /// Web does not support choosing a persistent backup folder.
  Future<BackupLocation?> pickLocation({BackupLocation? initial}) async {
    return null;
  }

  /// No default desktop location on web.
  Future<BackupLocation?> getDefaultDesktopLocation() async => null;

  /// Verifies the saved backup location.
  ///
  /// On web a persisted location is never valid.
  Future<bool> isLocationValid(BackupLocation location) async => false;

  /// Picks a backup file for restore and returns its bytes.
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

  /// Writes a backup by triggering a browser download.
  ///
  /// [location] and [defaultLocation] are ignored on web; the browser always
  /// asks the user where to save the downloaded file.
  Future<BackupWriteResult> saveBackup({
    required Uint8List bytes,
    required String defaultFileName,
    BackupLocation? location,
    BackupLocation? defaultLocation,
  }) async {
    try {
      final data = bytes.buffer.toJS;
      final blobParts = [data].toJS as JSArray<web.BlobPart>;
      final blob = web.Blob(blobParts, web.BlobPropertyBag(type: _downloadMimeType));
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = _ensureDbExtension(defaultFileName);

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);

      return BackupWriteResult(
        success: true,
        storageReference: defaultFileName,
        displayName: defaultFileName,
        fileSize: bytes.length,
        writtenTo: const BackupLocation(
          type: BackupStorageType.webDownload,
          reference: '',
          displayName: 'Browser download',
        ),
      );
    } catch (e) {
      return BackupWriteResult(
        success: false,
        error: 'Could not start the browser download: $e',
      );
    }
  }

  /// Web cannot re-read a previously downloaded file without the user
  /// picking it again.
  Future<BackupReadResult> readBackup(String reference) async {
    return const BackupReadResult(
      success: false,
      error: 'Web browsers cannot re-open a previously downloaded file. '
          'Please use the Choose Backup File option instead.',
    );
  }

  /// Returns the display name for a saved reference.
  Future<String> getDisplayName(String reference) async {
    return reference;
  }

  /// Returns the display name for a backup location.
  String getLocationDisplayName(BackupLocation location) {
    if (location.isNone) return '';
    return location.displayName.isNotEmpty
        ? location.displayName
        : 'Browser download';
  }

  /// No-op on web.
  Future<bool> deleteBackup(String reference) async => true;

  /// No-op on web.
  Future<void> releaseUri(String reference) async {}

  String _ensureDbExtension(String name) {
    if (!name.toLowerCase().endsWith('.db')) return '$name.db';
    return name;
  }
}
