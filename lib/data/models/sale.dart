class Sale {
  final int? id;
  final double totalAmount;
  final double cashReceived;
  final double change;
  final String paymentMethod;
  final String paymentStatus;
  final String? referenceNumber;
  final String? customerName;
  final String? paymentProofPath;
  final String? paymentProofType;
  final DateTime? verifiedAt;
  final int? verifiedBy;
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
    this.paymentMethod = 'Cash',
    this.paymentStatus = 'confirmed',
    this.referenceNumber,
    this.customerName,
    this.paymentProofPath,
    this.paymentProofType,
    this.verifiedAt,
    this.verifiedBy,
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
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'reference_number': referenceNumber,
      'customer_name': customerName,
      'payment_proof_path': paymentProofPath,
      'payment_proof_type': paymentProofType,
      'verified_at': verifiedAt?.toIso8601String(),
      'verified_by': verifiedBy,
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
      paymentMethod: (map['payment_method'] as String?) ?? 'Cash',
      paymentStatus: (map['payment_status'] as String?) ?? 'confirmed',
      referenceNumber: map['reference_number'] as String?,
      customerName: map['customer_name'] as String?,
      paymentProofPath: map['payment_proof_path'] as String?,
      paymentProofType: map['payment_proof_type'] as String?,
      verifiedAt: map['verified_at'] != null
          ? DateTime.parse(map['verified_at'] as String)
          : null,
      verifiedBy: map['verified_by'] as int?,
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
    String? paymentMethod,
    String? paymentStatus,
    String? referenceNumber,
    String? customerName,
    String? paymentProofPath,
    String? paymentProofType,
    DateTime? verifiedAt,
    int? verifiedBy,
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
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      customerName: customerName ?? this.customerName,
      paymentProofPath: paymentProofPath ?? this.paymentProofPath,
      paymentProofType: paymentProofType ?? this.paymentProofType,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      notes: notes ?? this.notes,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;

  /// Whether this sale is considered a completed/paid sale.
  bool get isConfirmed => paymentStatus == 'confirmed';

  /// Whether this sale is pending payment verification.
  bool get isPending => paymentStatus == 'pending';

  /// Whether this sale has been cancelled or refunded.
  bool get isCancelled => paymentStatus == 'cancelled' || paymentStatus == 'refunded';
}
