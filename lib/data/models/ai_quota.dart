class AIQuota {
  final int? id;
  final int userId;
  final int dailyQuota;
  final int dailyUsage;
  final DateTime quotaDate;
  final DateTime? lastResetAt;

  AIQuota({
    this.id,
    required this.userId,
    required this.dailyQuota,
    required this.dailyUsage,
    required this.quotaDate,
    this.lastResetAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'daily_quota': dailyQuota,
      'daily_usage': dailyUsage,
      'quota_date': quotaDate.toIso8601String(),
      'last_reset_at': lastResetAt?.toIso8601String(),
    };
  }

  factory AIQuota.fromMap(Map<String, dynamic> map) {
    return AIQuota(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      dailyQuota: map['daily_quota'] as int,
      dailyUsage: map['daily_usage'] as int? ?? 0,
      quotaDate: DateTime.parse(map['quota_date'] as String),
      lastResetAt: map['last_reset_at'] != null
          ? DateTime.parse(map['last_reset_at'] as String)
          : null,
    );
  }

  AIQuota copyWith({
    int? id,
    int? userId,
    int? dailyQuota,
    int? dailyUsage,
    DateTime? quotaDate,
    DateTime? lastResetAt,
  }) {
    return AIQuota(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      dailyQuota: dailyQuota ?? this.dailyQuota,
      dailyUsage: dailyUsage ?? this.dailyUsage,
      quotaDate: quotaDate ?? this.quotaDate,
      lastResetAt: lastResetAt ?? this.lastResetAt,
    );
  }
}
