/// A focused DTO for the automatic backup schedule.
///
/// This is intentionally separate from [Settings] so the UI and the
/// scheduler can pass the schedule around without carrying the full store
/// configuration.
class AutoBackupSettings {
  final bool enabled;
  final String frequency;
  final String time;
  final DateTime? lastRun;

  /// When the schedule was last saved. Anchors the schedule to a fixed
  /// date so the next run does not drift forward with the current date.
  final DateTime? scheduledAt;

  const AutoBackupSettings({
    this.enabled = false,
    this.frequency = '7_days',
    this.time = '02:00',
    this.lastRun,
    this.scheduledAt,
  });

  AutoBackupSettings copyWith({
    bool? enabled,
    String? frequency,
    String? time,
    Object? lastRun = _sentinel,
    Object? scheduledAt = _sentinel,
  }) =>
      AutoBackupSettings(
        enabled: enabled ?? this.enabled,
        frequency: frequency ?? this.frequency,
        time: time ?? this.time,
        lastRun: lastRun == _sentinel ? this.lastRun : lastRun as DateTime?,
        scheduledAt: scheduledAt == _sentinel
            ? this.scheduledAt
            : scheduledAt as DateTime?,
      );

  /// The next scheduled run for display: the first slot after the current
  /// time on the anchored schedule grid.
  DateTime? get nextRun => computeNextRun(this);

  /// The pending scheduled run: the first slot after the schedule anchor
  /// (the later of [lastRun] and [scheduledAt]). A pending run at or before
  /// the current time is due to execute.
  DateTime? get pendingRun => computePendingRun(this);

  /// Whether a scheduled run is due at [now] (defaults to the current
  /// time): a pending run exists and has been reached.
  bool isDue({DateTime? now}) {
    final pending = pendingRun;
    if (pending == null) return false;
    return !pending.isAfter(now ?? DateTime.now());
  }

  /// The moment the schedule grid is anchored to: the later of the last
  /// completed run and the last time the schedule was saved. Returns null
  /// when neither exists (schedule never saved through the new flow).
  static DateTime? _anchor(AutoBackupSettings settings) {
    final lastRun = settings.lastRun;
    final scheduledAt = settings.scheduledAt;
    if (lastRun == null) return scheduledAt;
    if (scheduledAt == null) return lastRun;
    return lastRun.isAfter(scheduledAt) ? lastRun : scheduledAt;
  }

  static (int, int) _parseTime(String time) {
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]) ?? 2;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour, minute);
  }

  /// Computes the next scheduled run using [settings] and an optional [now]
  /// timestamp. When [now] is omitted, the actual current time is used.
  ///
  /// This is the display value: the first slot after [now] on the anchored
  /// schedule grid. Because it is anchored to a saved date, it stays fixed
  /// instead of moving forward day by day.
  static DateTime? computeNextRun(
    AutoBackupSettings settings, {
    DateTime? now,
  }) {
    if (!settings.enabled) return null;

    final effectiveNow = now ?? DateTime.now();
    final (hour, minute) = _parseTime(settings.time);
    final anchor = _anchor(settings) ?? effectiveNow;
    final lowerBound =
        anchor.isAfter(effectiveNow) ? anchor : effectiveNow;

    var base = DateTime(anchor.year, anchor.month, anchor.day, hour, minute);
    while (!base.isAfter(lowerBound)) {
      base = _addFrequency(base, settings.frequency);
    }
    return base;
  }

  /// Computes the pending scheduled run: the first slot after the schedule
  /// anchor. When the result is at or before [now] (or the real current
  /// time), a backup is due.
  ///
  /// Returns null when the schedule has no anchor yet (never saved and
  /// never run).
  static DateTime? computePendingRun(
    AutoBackupSettings settings, {
    DateTime? now,
  }) {
    if (!settings.enabled) return null;

    final anchor = _anchor(settings);
    if (anchor == null) return null;

    final (hour, minute) = _parseTime(settings.time);
    var base = DateTime(anchor.year, anchor.month, anchor.day, hour, minute);
    while (!base.isAfter(anchor)) {
      base = _addFrequency(base, settings.frequency);
    }
    return base;
  }

  static DateTime _addFrequency(DateTime from, String frequency) {
    switch (frequency) {
      case 'daily':
        return from.add(const Duration(days: 1));
      case '3_days':
        return from.add(const Duration(days: 3));
      case '7_days':
        return from.add(const Duration(days: 7));
      case 'monthly':
        final nextMonth = from.month == 12 ? 1 : from.month + 1;
        final nextYear = from.month == 12 ? from.year + 1 : from.year;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        final day = from.day > lastDay ? lastDay : from.day;
        return DateTime(nextYear, nextMonth, day, from.hour, from.minute);
      default:
        return from.add(const Duration(days: 7));
    }
  }

  static const Object _sentinel = Object();
}
