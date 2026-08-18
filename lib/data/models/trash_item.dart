class TrashItem {
  final int? id;
  final String entityType;
  final int entityId;
  final String? entityName;
  final int? deletedBy;
  final DateTime deletedAt;
  final DateTime? expiresAt;

  TrashItem({
    this.id,
    required this.entityType,
    required this.entityId,
    this.entityName,
    this.deletedBy,
    required this.deletedAt,
    this.expiresAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'entity_name': entityName,
      'deleted_by': deletedBy,
      'deleted_at': deletedAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  factory TrashItem.fromMap(Map<String, dynamic> map) {
    return TrashItem(
      id: map['id'] as int?,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int,
      entityName: map['entity_name'] as String?,
      deletedBy: map['deleted_by'] as int?,
      deletedAt: DateTime.parse(map['deleted_at'] as String),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
    );
  }

  TrashItem copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? entityName,
    int? deletedBy,
    DateTime? deletedAt,
    DateTime? expiresAt,
  }) {
    return TrashItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      entityName: entityName ?? this.entityName,
      deletedBy: deletedBy ?? this.deletedBy,
      deletedAt: deletedAt ?? this.deletedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
