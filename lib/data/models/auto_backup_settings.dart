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

  const AutoBackupSettings({
    this.enabled = false,
    this.frequency = '7_days',
    this.time = '02:00',
    this.lastRun,
  });

  AutoBackupSettings copyWith({
    bool? enabled,
    String? frequency,
    String? time,
    Object? lastRun = _sentinel,
  }) =>
      AutoBackupSettings(
        enabled: enabled ?? this.enabled,
        frequency: frequency ?? this.frequency,
        time: time ?? this.time,
        lastRun: lastRun == _sentinel ? this.lastRun : lastRun as DateTime?,
      );

  /// The next scheduled run based on [lastRun] and the current time.
  DateTime? get nextRun => computeNextRun(this);

  /// Computes the next scheduled run using [settings] and an optional [now]
  /// timestamp. When [now] is omitted, the actual current time is used.
  static DateTime? computeNextRun(
    AutoBackupSettings settings, {
    DateTime? now,
  }) {
    if (!settings.enabled) return null;

    final effectiveNow = now ?? DateTime.now();
    final timeParts = settings.time.split(':');
    final hour = int.tryParse(timeParts[0]) ?? 2;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    DateTime base;
    if (settings.lastRun == null) {
      base = DateTime(
        effectiveNow.year,
        effectiveNow.month,
        effectiveNow.day,
        hour,
        minute,
      );
      if (base.isBefore(effectiveNow) ||
          base.isAtSameMomentAs(effectiveNow)) {
        base = _addFrequency(base, settings.frequency);
      }
    } else {
      base = DateTime(
        settings.lastRun!.year,
        settings.lastRun!.month,
        settings.lastRun!.day,
        hour,
        minute,
      );
      base = _addFrequency(base, settings.frequency);
    }

    while (base.isBefore(effectiveNow) ||
        base.isAtSameMomentAs(effectiveNow)) {
      base = _addFrequency(base, settings.frequency);
    }

    return base;
  }

  static DateTime _addFrequency(DateTime from, String frequency) {
    switch (frequency) {
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
