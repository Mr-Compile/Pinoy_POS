/// One day of aggregated sales for trend charts and reports.
class DailySalesPoint {
  final DateTime date;
  final double total;
  final int count;

  const DailySalesPoint({
    required this.date,
    required this.total,
    this.count = 0,
  });

  /// Alias for [count], used by dashboard code that labels the field
  /// as a transaction count.
  int get transactionCount => count;

  DailySalesPoint copyWith({
    DateTime? date,
    double? total,
    int? count,
  }) {
    return DailySalesPoint(
      date: date ?? this.date,
      total: total ?? this.total,
      count: count ?? this.count,
    );
  }

  factory DailySalesPoint.fromMap(Map<String, dynamic> map) {
    return DailySalesPoint(
      date: map['date'] != null
          ? DateTime.parse(map['date'] as String)
          : DateTime(1970),
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'DailySalesPoint(date: $date, total: $total, count: $count)';
  }
}
