import 'package:pinoy_pos/core/date_utils.dart';

/// Available reporting periods for sales analytics and reports.
enum ReportingPeriod {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  last7Days,
  last30Days,
  last90Days,
  custom;

  /// Human-readable label for the period selector.
  String get displayName => switch (this) {
        today => 'Today',
        yesterday => 'Yesterday',
        thisWeek => 'This Week',
        lastWeek => 'Last Week',
        thisMonth => 'This Month',
        lastMonth => 'Last Month',
        thisYear => 'This Year',
        lastYear => 'Last Year',
        last7Days => 'Last 7 Days',
        last30Days => 'Last 30 Days',
        last90Days => 'Last 90 Days',
        custom => 'Custom',
      };

  /// Short label for chips and compact UIs.
  String get shortName => switch (this) {
        today => 'Today',
        yesterday => 'Yest.',
        thisWeek => 'Week',
        lastWeek => 'L. Week',
        thisMonth => 'Month',
        lastMonth => 'L. Month',
        thisYear => 'Year',
        lastYear => 'L. Year',
        last7Days => '7 Days',
        last30Days => '30 Days',
        last90Days => '90 Days',
        custom => 'Custom',
      };
}

/// How the trend data should be grouped for a selected period.
enum ReportGroupBy {
  hour,
  day,
  week,
  month;

  String get displayName => switch (this) {
        hour => 'By Hour',
        day => 'By Day',
        week => 'By Week',
        month => 'By Month',
      };
}

/// Resolved start/end and previous-period bounds for a [ReportingPeriod].
class ReportingPeriodBounds {
  /// Inclusive start of the current period (midnight).
  final DateTime start;

  /// Exclusive end of the current period (midnight of the day after it ends).
  final DateTime end;

  /// Inclusive start of the previous comparable period.
  final DateTime previousStart;

  /// Exclusive end of the previous comparable period.
  final DateTime previousEnd;

  /// The natural grouping for trend data for these bounds.
  final ReportGroupBy groupBy;

  const ReportingPeriodBounds({
    required this.start,
    required this.end,
    required this.previousStart,
    required this.previousEnd,
    required this.groupBy,
  });

  /// Whether this is a custom range (used for labeling).
  bool get isCustom => false;

  /// The number of days the current period covers.
  int get dayCount => end.difference(start).inDays;

  @override
  String toString() {
    return 'ReportingPeriodBounds($start → $end, prev $previousStart → $previousEnd, $groupBy)';
  }
}

/// Custom period bounds supplied by the user.
class CustomPeriodBounds extends ReportingPeriodBounds {
  final String label;

  CustomPeriodBounds({
    required DateTime start,
    required DateTime end,
    this.label = 'Custom Range',
  }) : super(
          start: startOfDay(start),
          end: startOfDay(end).add(const Duration(days: 1)),
          previousStart: _previousPeriodStart(start, end),
          previousEnd: startOfDay(start),
          groupBy: _groupByForRange(start, end),
        );

  @override
  bool get isCustom => true;

  @override
  String toString() => label;
}

/// Returns the bounds for a [ReportingPeriod] anchored at [anchor].
ReportingPeriodBounds periodBoundsFor(
  ReportingPeriod period, {
  DateTime? anchor,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final now = anchor ?? DateTime.now();
  final today = startOfDay(now);

  switch (period) {
    case ReportingPeriod.today:
      return ReportingPeriodBounds(
        start: today,
        end: today.add(const Duration(days: 1)),
        previousStart: today.subtract(const Duration(days: 1)),
        previousEnd: today,
        groupBy: ReportGroupBy.hour,
      );
    case ReportingPeriod.yesterday:
      final start = today.subtract(const Duration(days: 1));
      return ReportingPeriodBounds(
        start: start,
        end: today,
        previousStart: start.subtract(const Duration(days: 1)),
        previousEnd: start,
        groupBy: ReportGroupBy.hour,
      );
    case ReportingPeriod.thisWeek:
      final start = startOfWeek(today);
      final end = start.add(const Duration(days: 7));
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(const Duration(days: 7)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.lastWeek:
      final start = startOfWeek(today).subtract(const Duration(days: 7));
      final end = start.add(const Duration(days: 7));
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(const Duration(days: 7)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      final end = DateTime(today.year, today.month + 1, 1);
      final days = end.difference(start).inDays;
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(Duration(days: days)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.lastMonth:
      final start = DateTime(today.year, today.month - 1, 1);
      final end = DateTime(today.year, today.month, 1);
      final days = end.difference(start).inDays;
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: start.subtract(Duration(days: days)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.thisYear:
      final start = DateTime(today.year, 1, 1);
      final end = DateTime(today.year + 1, 1, 1);
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: DateTime(today.year - 1, 1, 1),
        previousEnd: start,
        groupBy: ReportGroupBy.month,
      );
    case ReportingPeriod.lastYear:
      final start = DateTime(today.year - 1, 1, 1);
      final end = DateTime(today.year, 1, 1);
      return ReportingPeriodBounds(
        start: start,
        end: end,
        previousStart: DateTime(today.year - 2, 1, 1),
        previousEnd: start,
        groupBy: ReportGroupBy.month,
      );
    case ReportingPeriod.last7Days:
      final start = today.subtract(const Duration(days: 6));
      return ReportingPeriodBounds(
        start: start,
        end: today.add(const Duration(days: 1)),
        previousStart: start.subtract(const Duration(days: 7)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.last30Days:
      final start = today.subtract(const Duration(days: 29));
      return ReportingPeriodBounds(
        start: start,
        end: today.add(const Duration(days: 1)),
        previousStart: start.subtract(const Duration(days: 30)),
        previousEnd: start,
        groupBy: ReportGroupBy.day,
      );
    case ReportingPeriod.last90Days:
      final start = today.subtract(const Duration(days: 89));
      return ReportingPeriodBounds(
        start: start,
        end: today.add(const Duration(days: 1)),
        previousStart: start.subtract(const Duration(days: 90)),
        previousEnd: start,
        groupBy: ReportGroupBy.week,
      );
    case ReportingPeriod.custom:
      if (customStart == null || customEnd == null) {
        // Fall back to the current month when no custom range is supplied.
        final start = DateTime(today.year, today.month, 1);
        final end = today.add(const Duration(days: 1));
        return CustomPeriodBounds(start: start, end: end, label: 'This Month');
      }
      return CustomPeriodBounds(start: customStart, end: customEnd);
  }
}

/// Format a bounds range as a human-readable label.
String formatPeriodLabel(ReportingPeriodBounds bounds, {String? customLabel}) {
  if (bounds is CustomPeriodBounds) return customLabel ?? bounds.label;
  if (bounds.dayCount == 1) return _shortDate(bounds.start);

  final start = _shortDate(bounds.start);
  final end = _shortDate(bounds.end.subtract(const Duration(days: 1)));
  if (start == end) return start;
  return '$start – $end';
}

DateTime startOfWeek(DateTime date) {
  // Week starts on Monday (weekday 1 = Monday, 7 = Sunday).
  final offset = date.weekday - DateTime.monday;
  return startOfDay(date.subtract(Duration(days: offset)));
}

DateTime _previousPeriodStart(DateTime start, DateTime end) {
  final days = end.difference(start).inDays;
  return startOfDay(start).subtract(Duration(days: days));
}

ReportGroupBy _groupByForRange(DateTime start, DateTime end) {
  final days = end.difference(start).inDays;
  if (days <= 1) return ReportGroupBy.hour;
  if (days <= 31) return ReportGroupBy.day;
  if (days <= 120) return ReportGroupBy.week;
  return ReportGroupBy.month;
}

String _shortDate(DateTime date) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
