class ActivityLog {
  final int? id;
  final int userId;
  final String action;
  final String? entity;
  final int? entityId;
  final String? details;
  final DateTime createdAt;

  ActivityLog({
    this.id,
    required this.userId,
    required this.action,
    this.entity,
    this.entityId,
    this.details,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ActivityLog.fromMap(Map<String, dynamic> map) {
    return ActivityLog(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      action: map['action'] as String,
      entity: map['entity'] as String?,
      entityId: map['entity_id'] as int?,
      details: map['details'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  ActivityLog copyWith({
    int? id,
    int? userId,
    String? action,
    String? entity,
    int? entityId,
    String? details,
    DateTime? createdAt,
  }) {
    return ActivityLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      action: action ?? this.action,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
