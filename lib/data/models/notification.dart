class Notification {
  final int? id;
  final String title;
  final String message;
  final String? type;
  final int? userId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  Notification({
    this.id,
    required this.title,
    required this.message,
    this.type,
    this.userId,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type,
      'user_id': userId,
      'is_read': isRead ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  factory Notification.fromMap(Map<String, dynamic> map) {
    return Notification(
      id: map['id'] as int?,
      title: map['title'] as String,
      message: map['message'] as String,
      type: map['type'] as String?,
      userId: map['user_id'] as int?,
      isRead: (map['is_read'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
    );
  }

  Notification copyWith({
    int? id,
    String? title,
    String? message,
    String? type,
    int? userId,
    bool? isRead,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return Notification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      userId: userId ?? this.userId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}
