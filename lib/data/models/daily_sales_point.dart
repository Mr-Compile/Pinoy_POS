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

  @override
  String toString() {
    return 'DailySalesPoint(date: $date, total: $total, count: $count)';
  }
}
