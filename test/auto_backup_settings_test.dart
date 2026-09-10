import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/data/models/auto_backup_settings.dart';

void main() {
  group('AutoBackupSettings.computeNextRun', () {
    final now = DateTime(2026, 9, 15, 12, 0);

    test('returns null when disabled', () {
      final settings = AutoBackupSettings(
        enabled: false,
        frequency: '7_days',
        time: '02:00',
      );
      expect(AutoBackupSettings.computeNextRun(settings, now: now), isNull);
    });

    test('returns today at the configured time when it has not passed', () {
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '20:00',
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 15, 20, 0));
    });

    test('advances by the configured frequency when no last run and time passed', () {
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '02:00',
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 22, 2, 0));
    });

    test('advances by 3 days and catches up if that slot is in the past', () {
      final lastRun = DateTime(2026, 9, 10, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '3_days',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 16, 2, 0));
    });

    test('advances by 7 days and catches up if that slot is in the past', () {
      final lastRun = DateTime(2026, 9, 5, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 19, 2, 0));
    });

    test('advances by one month for monthly frequency', () {
      final lastRun = DateTime(2026, 9, 10, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: 'monthly',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 10, 10, 2, 0));
    });

    test('clamps monthly day and catches up to the first future month', () {
      final lastRun = DateTime(2026, 1, 31, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: 'monthly',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 28, 2, 0));
    });

    test('skips missed monthly periods and returns the first future occurrence', () {
      final lastRun = DateTime(2026, 6, 1, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: 'monthly',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 10, 1, 2, 0));
    });

    test('respects the configured time', () {
      final lastRun = DateTime(2026, 9, 10, 14, 30);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '04:30',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 17, 4, 30));
    });

    test('returns the same future slot when it has not passed', () {
      final lastRun = DateTime(2026, 9, 10, 2, 0);
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '02:00',
        lastRun: lastRun,
      );
      final next = AutoBackupSettings.computeNextRun(settings, now: now)!;
      expect(next, DateTime(2026, 9, 17, 2, 0));
    });
  });

  group('AutoBackupSettings.nextRun', () {
    test('getter matches computeNextRun with DateTime.now()', () {
      final settings = AutoBackupSettings(
        enabled: true,
        frequency: '7_days',
        time: '02:00',
      );
      final now = DateTime.now();
      final expected = AutoBackupSettings.computeNextRun(settings, now: now)!;
      final actual = settings.nextRun!;
      expect(actual.year, expected.year);
      expect(actual.month, expected.month);
      expect(actual.day, expected.day);
      expect(actual.hour, expected.hour);
      expect(actual.minute, expected.minute);
    });
  });
}
