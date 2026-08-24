import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Platform-agnostic storage representation for a backup location.
///
/// The [reference] may be:
/// - a Windows/Linux/macOS filesystem path
/// - an Android Storage Access Framework (SAF) content URI
/// - a web download filename or empty on unsupported platforms
///
/// The [displayName] is a human-readable label like
/// "Documents › Pinoy POS Backups" and should never be a raw
/// implementation identifier.
enum BackupStorageType { fileSystem, androidSaf, webDownload }

class BackupLocation {
  final BackupStorageType type;

  /// The actual platform storage reference:
  /// - [fileSystem]: absolute directory path
  /// - [androidSaf]: persisted tree URI string
  /// - [webDownload]: empty (web cannot persist a folder)
  final String reference;

  /// Human-readable name for display in the UI.
  final String displayName;

  const BackupLocation({
    required this.type,
    required this.reference,
    required this.displayName,
  });

  const BackupLocation.none()
      : type = BackupStorageType.fileSystem,
        reference = '',
        displayName = '';

  bool get isNone => reference.isEmpty;

  bool get supportsFolderSelection =>
      type == BackupStorageType.fileSystem ||
      type == BackupStorageType.androidSaf;

  BackupLocation copyWith({
    BackupStorageType? type,
    String? reference,
    String? displayName,
  }) {
    return BackupLocation(
      type: type ?? this.type,
      reference: reference ?? this.reference,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'reference': reference,
        'displayName': displayName,
      };

  factory BackupLocation.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'fileSystem';
    return BackupLocation(
      type: BackupStorageType.values.byName(typeName),
      reference: (json['reference'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory BackupLocation.fromJsonString(String jsonString) {
    if (jsonString.isEmpty) return const BackupLocation.none();
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return BackupLocation.fromJson(map);
    } catch (e) {
      debugPrint('[BackupLocation] Failed to parse saved location: $e');
      return const BackupLocation.none();
    }
  }

  @override
  String toString() => 'BackupLocation($type, $displayName)';
}

/// Result of writing a backup to a chosen storage location.
class BackupWriteResult {
  final bool success;
  final String? error;

  /// The storage reference of the saved backup (path or URI).
  final String? storageReference;

  /// The filename shown in the UI.
  final String? displayName;

  /// The size in bytes of the written backup.
  final int? fileSize;

  /// The location where the file was written (for UI display).
  final BackupLocation? writtenTo;

  const BackupWriteResult({
    required this.success,
    this.error,
    this.storageReference,
    this.displayName,
    this.fileSize,
    this.writtenTo,
  });
}

/// A selected backup file for restore.
class BackupReadResult {
  final bool success;
  final String? error;

  /// Raw backup bytes. Non-null when [success] is true.
  final Uint8List? bytes;

  /// The filename shown to the user.
  final String? displayName;

  /// The file size in bytes.
  final int? fileSize;

  const BackupReadResult({
    required this.success,
    this.error,
    this.bytes,
    this.displayName,
    this.fileSize,
  });
}

