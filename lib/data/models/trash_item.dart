import 'dart:convert';

class TrashItem {
  final int? id;
  final String entityType;
  final int entityId;
  final String? entityName;
  final String? snapshotJson;
  final int? deletedBy;
  final String? deletedByName;
  final DateTime deletedAt;
  final DateTime? expiresAt;
  final int attachmentCount;
  final int totalSizeBytes;

  TrashItem({
    this.id,
    required this.entityType,
    required this.entityId,
    this.entityName,
    this.snapshotJson,
    this.deletedBy,
    this.deletedByName,
    required this.deletedAt,
    this.expiresAt,
    this.attachmentCount = 0,
    this.totalSizeBytes = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'entity_name': entityName,
      'snapshot_json': snapshotJson,
      'deleted_by': deletedBy,
      'deleted_at': deletedAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'attachment_count': attachmentCount,
      'total_size_bytes': totalSizeBytes,
    };
  }

  factory TrashItem.fromMap(Map<String, dynamic> map) {
    return TrashItem(
      id: map['id'] as int?,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int,
      entityName: map['entity_name'] as String?,
      snapshotJson: map['snapshot_json'] as String?,
      deletedBy: map['deleted_by'] as int?,
      deletedAt: DateTime.parse(map['deleted_at'] as String),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
      attachmentCount: (map['attachment_count'] as int?) ?? 0,
      totalSizeBytes: (map['total_size_bytes'] as int?) ?? 0,
    );
  }

  TrashItem copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? entityName,
    String? snapshotJson,
    int? deletedBy,
    String? deletedByName,
    DateTime? deletedAt,
    DateTime? expiresAt,
    int? attachmentCount,
    int? totalSizeBytes,
  }) {
    return TrashItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      entityName: entityName ?? this.entityName,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      deletedBy: deletedBy ?? this.deletedBy,
      deletedByName: deletedByName ?? this.deletedByName,
      deletedAt: deletedAt ?? this.deletedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
    );
  }

  /// Parses [snapshotJson] into a map. Returns null if the JSON is missing or
  /// invalid.
  Map<String, dynamic>? get snapshotMap {
    final json = snapshotJson;
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }
}
