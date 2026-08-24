class BackupHistory {
  final int? id;

  /// Storage reference: a filesystem path or a platform URI.
  final String filePath;

  /// Human-readable filename shown in the UI (e.g. the backup .db filename).
  final String? displayName;

  /// Storage type: fileSystem, androidSaf, or webDownload.
  /// Stored as a string in the database.
  final String? storageType;

  /// Persisted JSON of the [BackupLocation] where this backup was saved.
  /// Used to render a human-readable "Saved to:" line for each history row.
  final String? locationJson;

  final int? fileSize;
  final int? createdBy;
  final DateTime createdAt;

  BackupHistory({
    this.id,
    required this.filePath,
    this.displayName,
    this.storageType,
    this.locationJson,
    this.fileSize,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'display_name': displayName,
      'storage_type': storageType,
      'location_json': locationJson,
      'file_size': fileSize,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BackupHistory.fromMap(Map<String, dynamic> map) {
    return BackupHistory(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      displayName: map['display_name'] as String?,
      storageType: map['storage_type'] as String?,
      locationJson: map['location_json'] as String?,
      fileSize: map['file_size'] as int?,
      createdBy: map['created_by'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  BackupHistory copyWith({
    int? id,
    String? filePath,
    String? displayName,
    String? storageType,
    String? locationJson,
    int? fileSize,
    int? createdBy,
    DateTime? createdAt,
  }) {
    return BackupHistory(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      displayName: displayName ?? this.displayName,
      storageType: storageType ?? this.storageType,
      locationJson: locationJson ?? this.locationJson,
      fileSize: fileSize ?? this.fileSize,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
