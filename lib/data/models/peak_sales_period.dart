/// The busiest hour and day within a selected sales period.
///
/// [peakHour] is the hour-of-day (0-23) with the highest sales across the
/// entire range. [peakDay] is the specific day (or month start for yearly
/// ranges) with the highest sales.
class PeakSalesPeriod {
  final int? peakHour;
  final double peakHourSales;
  final int peakHourTransactions;
  final DateTime? peakDay;
  final double peakDaySales;
  final int peakDayTransactions;

  const PeakSalesPeriod({
    this.peakHour,
    this.peakHourSales = 0.0,
    this.peakHourTransactions = 0,
    this.peakDay,
    this.peakDaySales = 0.0,
    this.peakDayTransactions = 0,
  });

  factory PeakSalesPeriod.empty() => const PeakSalesPeriod();

  /// Human-readable hour label, e.g. "12 PM – 1 PM".
  String get peakHourLabel {
    if (peakHour == null) return 'No data';
    final start = peakHour!;
    final end = (start + 1) % 24;
    return '${_formatHour(start)} – ${_formatHour(end)}';
  }

  /// Human-readable day label, e.g. "Sep 2".
  String get peakDayLabel {
    if (peakDay == null) return 'No data';
    return _formatDate(peakDay!);
  }

  static String _formatHour(int hour) {
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$display $suffix';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  String toString() {
    return 'PeakSalesPeriod(hour: $peakHourLabel, day: $peakDayLabel)';
  }
}
