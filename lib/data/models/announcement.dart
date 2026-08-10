class Announcement {
  final int? id;
  final String title;
  final String content;
  final bool isPinned;
  final DateTime? expiresAt;
  final int? createdBy;
  final DateTime createdAt;
  final DateTime? deletedAt;

  Announcement({
    this.id,
    required this.title,
    required this.content,
    this.isPinned = false,
    this.expiresAt,
    this.createdBy,
    required this.createdAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'is_pinned': isPinned ? 1 : 0,
      'expires_at': expiresAt?.toIso8601String(),
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Announcement.fromMap(Map<String, dynamic> map) {
    return Announcement(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      isPinned: (map['is_pinned'] as int) == 1,
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
      createdBy: map['created_by'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Announcement copyWith({
    int? id,
    String? title,
    String? content,
    bool? isPinned,
    DateTime? expiresAt,
    int? createdBy,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Announcement(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isPinned: isPinned ?? this.isPinned,
      expiresAt: expiresAt ?? this.expiresAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
