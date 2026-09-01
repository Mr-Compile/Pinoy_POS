/// Sales total and transaction count for a single hour of the day (0-23).
class SalesByHourPoint {
  final int hour;
  final double total;
  final int count;

  const SalesByHourPoint({
    required this.hour,
    required this.total,
    required this.count,
  });

  factory SalesByHourPoint.fromMap(Map<String, dynamic> map) {
    final rawHour = map['hour'];
    return SalesByHourPoint(
      hour: rawHour is int ? rawHour : int.parse(rawHour as String),
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}
