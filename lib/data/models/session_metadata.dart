/// Persisted session metadata.
///
/// This is the source of truth for absolute session expiry and the last
/// recorded activity timestamp. It is stored separately from the in-memory
/// `SessionManager` state so expiry can be evaluated on the next app launch.
class SessionMetadata {
  final int userId;
  final DateTime sessionExpiresAt;
  final DateTime lastActivityAt;
  final bool pinVerified;

  SessionMetadata({
    required this.userId,
    required this.sessionExpiresAt,
    required this.lastActivityAt,
    required this.pinVerified,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'session_expires_at': sessionExpiresAt.toIso8601String(),
      'last_activity_at': lastActivityAt.toIso8601String(),
      'pin_verified': pinVerified ? 1 : 0,
    };
  }

  factory SessionMetadata.fromMap(Map<String, dynamic> map) {
    return SessionMetadata(
      userId: map['user_id'] as int,
      sessionExpiresAt: DateTime.parse(map['session_expires_at'] as String),
      lastActivityAt: DateTime.parse(map['last_activity_at'] as String),
      pinVerified: (map['pin_verified'] as int) == 1,
    );
  }

  SessionMetadata copyWith({
    int? userId,
    DateTime? sessionExpiresAt,
    DateTime? lastActivityAt,
    bool? pinVerified,
  }) {
    return SessionMetadata(
      userId: userId ?? this.userId,
      sessionExpiresAt: sessionExpiresAt ?? this.sessionExpiresAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      pinVerified: pinVerified ?? this.pinVerified,
    );
  }
}
