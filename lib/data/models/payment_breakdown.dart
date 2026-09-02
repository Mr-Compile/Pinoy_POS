/// Payment method totals used in reports and analytics.
class PaymentBreakdown {
  final String method;
  final double total;
  final int count;

  PaymentBreakdown({
    required this.method,
    required this.total,
    required this.count,
  });

  /// Percentage of the given [grandTotal], or 0.0 when there is no total.
  double percentageOf(double grandTotal) {
    if (grandTotal <= 0) return 0.0;
    return (total / grandTotal * 100);
  }

  factory PaymentBreakdown.fromMap(Map<String, dynamic> map) {
    return PaymentBreakdown(
      method: (map['payment_method'] as String?) ?? 'Unknown',
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'PaymentBreakdown($method: $count txns, $total)';
  }
}
