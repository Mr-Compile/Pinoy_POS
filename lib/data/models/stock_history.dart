enum StockOperationType {
  add,
  adjust,
  sale,
  return_,
}

class StockHistory {
  final int? id;
  final int productId;
  final StockOperationType operation;
  final int quantity;
  final int previousStock;
  final int newStock;
  final String? reason;
  final int? userId;
  final DateTime createdAt;

  StockHistory({
    this.id,
    required this.productId,
    required this.operation,
    required this.quantity,
    required this.previousStock,
    required this.newStock,
    this.reason,
    this.userId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'operation': operation.name,
      'quantity': quantity,
      'previous_stock': previousStock,
      'new_stock': newStock,
      'reason': reason,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockHistory.fromMap(Map<String, dynamic> map) {
    return StockHistory(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      operation: StockOperationType.values.firstWhere(
        (e) => e.name == map['operation'],
        orElse: () => StockOperationType.adjust,
      ),
      quantity: map['quantity'] as int,
      previousStock: map['previous_stock'] as int,
      newStock: map['new_stock'] as int,
      reason: map['reason'] as String?,
      userId: map['user_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  StockHistory copyWith({
    int? id,
    int? productId,
    StockOperationType? operation,
    int? quantity,
    int? previousStock,
    int? newStock,
    String? reason,
    int? userId,
    DateTime? createdAt,
  }) {
    return StockHistory(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      operation: operation ?? this.operation,
      quantity: quantity ?? this.quantity,
      previousStock: previousStock ?? this.previousStock,
      newStock: newStock ?? this.newStock,
      reason: reason ?? this.reason,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
