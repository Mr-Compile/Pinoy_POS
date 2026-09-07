import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart' hide startOfWeek;

/// The canonical calendar-based sales analytics granularities.
///
/// The dashboard and sales analytics screens use these values plus a custom
/// date range option. Hourly and preset ranges (Today, This Week, etc.) are
/// intentionally avoided in the active analytics UI.
enum SalesPeriod {
  daily,
  weekly,
  monthly,
  custom;

  String get displayName => switch (this) {
        daily => 'Daily',
        weekly => 'Weekly',
        monthly => 'Monthly',
        custom => 'Custom',
      };

  String get shortName => switch (this) {
        daily => 'D',
        weekly => 'W',
        monthly => 'M',
        custom => 'C',
      };
}

/// Shared filter state used by both the Dashboard and the Sales Analytics
/// screen.
///
/// [period] controls the granularity. [selectedDate] is the anchor the user
/// picked from the calendar and is always normalised to the start of the day.
/// For [SalesPeriod.weekly] the selected date determines the containing week
/// (Monday–Sunday). For [SalesPeriod.monthly] it determines the month.
class SalesPeriodFilter {
  final SalesPeriod period;
  final DateTime selectedDate;
  final DateTime? customEnd;

  SalesPeriodFilter({
    required this.period,
    required DateTime selectedDate,
    DateTime? customEnd,
  })  : selectedDate = startOfDay(selectedDate),
        customEnd = customEnd != null ? startOfDay(customEnd) : null;

  SalesPeriodFilter copyWith({
    SalesPeriod? period,
    DateTime? selectedDate,
    DateTime? customEnd,
    bool clearCustomEnd = false,
  }) {
    return SalesPeriodFilter(
      period: period ?? this.period,
      selectedDate: selectedDate != null ? startOfDay(selectedDate) : this.selectedDate,
      customEnd: clearCustomEnd
          ? null
          : (customEnd != null ? startOfDay(customEnd) : this.customEnd),
    );
  }

  /// A filter for today at the given [period].
  factory SalesPeriodFilter.today(SalesPeriod period) {
    return SalesPeriodFilter(
      period: period,
      selectedDate: startOfDay(DateTime.now()),
    );
  }

  DateTime get startOfPeriod => switch (period) {
        SalesPeriod.daily => selectedDate,
        SalesPeriod.weekly => startOfWeek(selectedDate),
        SalesPeriod.monthly => DateTime(selectedDate.year, selectedDate.month, 1),
        SalesPeriod.custom => selectedDate,
      };

  /// For [SalesPeriod.custom], returns the selected end date. For other periods
  /// it returns the computed exclusive end of the period.
  DateTime get endOfPeriod => switch (period) {
        SalesPeriod.daily => selectedDate.add(const Duration(days: 1)),
        SalesPeriod.weekly => startOfWeek(selectedDate).add(const Duration(days: 7)),
        SalesPeriod.monthly =>
          DateTime(selectedDate.year, selectedDate.month + 1, 1),
        SalesPeriod.custom =>
          (customEnd ?? selectedDate).add(const Duration(days: 1)),
      };

  @override
  String toString() => 'SalesPeriodFilter($period, $selectedDate, $customEnd)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SalesPeriodFilter &&
          other.period == period &&
          other.selectedDate.year == selectedDate.year &&
          other.selectedDate.month == selectedDate.month &&
          other.selectedDate.day == selectedDate.day &&
          other.customEnd?.year == customEnd?.year &&
          other.customEnd?.month == customEnd?.month &&
          other.customEnd?.day == customEnd?.day;

  @override
  int get hashCode => Object.hash(
        period,
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        customEnd?.year,
        customEnd?.month,
        customEnd?.day,
      );
}

/// Returns the [ReportingPeriodBounds] that correspond to [filter].
///
/// - Daily: the selected calendar day, previous day, day-level buckets.
/// - Weekly: Monday–Sunday of the selected week, previous week, day-level
///   buckets (the chart renders each day as a bar).
/// - Monthly: the selected calendar month, previous month, week-level
///   buckets anchored to the first of the month so the bars are "Week 1",
///   "Week 2", etc.
ReportingPeriodBounds boundsForSalesFilter(SalesPeriodFilter filter) {
  final selected = filter.selectedDate;
  switch (filter.period) {
    case SalesPeriod.daily:
      final start = selected;
      final end = selected.add(const Duration(days: 1));
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(const Duration(days: 1)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case SalesPeriod.weekly:
      final start = startOfWeek(selected);
      final end = start.add(const Duration(days: 7));
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(const Duration(days: 7)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case SalesPeriod.monthly:
      final start = DateTime(selected.year, selected.month, 1);
      final end = DateTime(selected.year, selected.month + 1, 1);
      final days = end.difference(start).inDays;
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(Duration(days: days)),
        previousEnd: start,
        groupBy: ReportGroupBy.week,
        weekAnchor: start,
      );
    case SalesPeriod.custom:
      final start = selected;
      final end = filter.endOfPeriod;
      final days = end.difference(start).inDays;
      final groupBy = days <= 31
          ? ReportGroupBy.day
          : days <= 120
              ? ReportGroupBy.week
              : ReportGroupBy.month;
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(Duration(days: days)),
        previousEnd: start,
        groupBy: groupBy,
        weekAnchor: groupBy == ReportGroupBy.week ? start : null,
      );
  }
}

/// Human-readable label for a [SalesPeriodFilter].
String formatSalesPeriodLabel(SalesPeriodFilter filter) {
  final selected = filter.selectedDate;
  switch (filter.period) {
    case SalesPeriod.daily:
      return '${selected.month}/${selected.day}/${selected.year}';
    case SalesPeriod.weekly:
      final start = startOfWeek(selected);
      final end = start.add(const Duration(days: 6));
      return '${_shortDate(start)} – ${_shortDate(end)}';
    case SalesPeriod.monthly:
      return _shortMonthYear(selected);
    case SalesPeriod.custom:
      final end = filter.customEnd;
      if (end == null) return 'Custom Range';
      return '${_shortDate(selected)} – ${_shortDate(end)}';
  }
}

String _shortDate(DateTime date) {
  return '${date.month}/${date.day}/${date.year}';
}

String _shortMonthYear(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
