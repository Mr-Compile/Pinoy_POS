/// Sales totals for a single calendar day used by the Owner sales calendar.
class CalendarDaySales {
  final DateTime date;
  final double totalSales;
  final int transactionCount;

  const CalendarDaySales({
    required this.date,
    required this.totalSales,
    required this.transactionCount,
  });

  double get averageTransaction =>
      transactionCount == 0 ? 0.0 : totalSales / transactionCount;

  factory CalendarDaySales.fromMap(Map<String, dynamic> map) {
    return CalendarDaySales(
      date: DateTime.parse(map['date'] as String),
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'CalendarDaySales($date: $transactionCount txns, $totalSales)';
  }
}
