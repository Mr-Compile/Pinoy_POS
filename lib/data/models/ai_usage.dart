class AIUsage {
  final int? id;
  final int userId;
  final String query;
  final String? response;
  final DateTime createdAt;

  AIUsage({
    this.id,
    required this.userId,
    required this.query,
    this.response,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'query': query,
      'response': response,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AIUsage.fromMap(Map<String, dynamic> map) {
    return AIUsage(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      query: map['query'] as String,
      response: map['response'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  AIUsage copyWith({
    int? id,
    int? userId,
    String? query,
    String? response,
    DateTime? createdAt,
  }) {
    return AIUsage(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      query: query ?? this.query,
      response: response ?? this.response,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
