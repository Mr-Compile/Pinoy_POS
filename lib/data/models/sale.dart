class Sale {
  final int? id;
  final double totalAmount;
  final double cashReceived;
  final double change;
  final int userId;
  final DateTime createdAt;
  final String? receiptNumber;
  final String? notes;
  final DateTime? deletedAt;

  Sale({
    this.id,
    required this.totalAmount,
    required this.cashReceived,
    required this.change,
    required this.userId,
    required this.createdAt,
    this.receiptNumber,
    this.notes,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'total_amount': totalAmount,
      'cash_received': cashReceived,
      'change': change,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'receipt_number': receiptNumber,
      'notes': notes,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as int?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      cashReceived: (map['cash_received'] as num).toDouble(),
      change: (map['change'] as num).toDouble(),
      userId: map['user_id'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      receiptNumber: map['receipt_number'] as String?,
      notes: map['notes'] as String?,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Sale copyWith({
    int? id,
    double? totalAmount,
    double? cashReceived,
    double? change,
    int? userId,
    DateTime? createdAt,
    String? receiptNumber,
    String? notes,
    DateTime? deletedAt,
  }) {
    return Sale(
      id: id ?? this.id,
      totalAmount: totalAmount ?? this.totalAmount,
      cashReceived: cashReceived ?? this.cashReceived,
      change: change ?? this.change,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      notes: notes ?? this.notes,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;
}
