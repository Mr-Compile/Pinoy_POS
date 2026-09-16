import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/widgets/license_notice.dart';

/// In-memory [LicenseStore] so tests never touch platform channels.
class MemoryLicenseStore implements LicenseStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late DateTime now;
  late LicenseService service;

  setUp(() {
    now = DateTime(2026, 9, 14, 12, 0);
    service = LicenseService(
      stateStore: MemoryLicenseStore(),
      markerStore: MemoryLicenseStore(),
      clock: () => now,
    );
  });

  /// Satisfies the activation gate — devices start unactivated, and an
  /// unactivated device never shows the countdown strip.
  Future<void> activate() async {
    await service.redeemActivationCode(service.activationCode());
  }

  Future<void> pumpNotice(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [licenseServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: Scaffold(body: LicenseNotice())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('calm tier', () {
    testWidgets('shows a trial countdown for short terms', (tester) async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      await pumpNotice(tester);

      expect(find.text('Trial · 30 days left'), findsOneWidget);
      expect(find.text('Enter code'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('shows a license countdown for longer terms', (tester) async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 90)),
      );
      await activate();
      await pumpNotice(tester);

      expect(find.text('License · 90 days left'), findsOneWidget);
    });
  });

  group('warn tier', () {
    testWidgets('shows "expires in" copy inside the warning window', (
      tester,
    ) async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      // 5 days remain — inside the proportional warning window (7.5d).
      now = now.add(const Duration(days: 25));
      await pumpNotice(tester);

      expect(find.text('Trial expires in 5 days'), findsOneWidget);
      expect(find.textContaining('Enter a code to extend'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('critical tier', () {
    testWidgets('shows "locks in" copy and contact in the final 48h', (
      tester,
    ) async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
        contactInfo: 'Dev 0917',
      );
      await activate();
      // 20 hours remain — inside warning window AND critical window.
      now = now.add(const Duration(days: 29, hours: 4));
      await pumpNotice(tester);

      expect(find.text('Trial locks in 20 hours'), findsOneWidget);
      expect(
        find.textContaining('Enter a code or contact Dev 0917'),
        findsOneWidget,
      );
    });

    testWidgets('critical is a sub-tier of warn — never shows before the '
        'warning window', (tester) async {
      // 4-day term → warning threshold is 1 day (min window), critical
      // window is 48h. At 36h left the strip must still be calm/warn,
      // not critical.
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 4)),
      );
      await activate();
      now = now.add(const Duration(hours: 60)); // 36h remain
      await pumpNotice(tester);

      final status = await service.evaluate();
      expect(status.isExpiringSoon, isFalse);
      expect(status.isCritical, isFalse);
      // Calm tier — formatRemaining rounds 36h down to "1 day".
      expect(find.text('Trial · 1 day left'), findsOneWidget);
    });
  });

  group('hidden', () {
    testWidgets('renders nothing when no license is configured', (
      tester,
    ) async {
      await pumpNotice(tester);

      expect(tester.getSize(find.byType(LicenseNotice)), Size.zero);
    });

    testWidgets('renders nothing when the license is disarmed', (tester) async {
      await service.saveConfig(armed: false);
      await pumpNotice(tester);

      expect(tester.getSize(find.byType(LicenseNotice)), Size.zero);
    });

    testWidgets('renders nothing when expired — the lock screen takes '
        'over', (tester) async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      now = now.add(const Duration(days: 31));
      await pumpNotice(tester);

      expect(tester.getSize(find.byType(LicenseNotice)), Size.zero);
    });
  });

  testWidgets('enter code opens the shared unlock dialog', (tester) async {
    await service.saveConfig(
      armed: true,
      expiresAt: now.add(const Duration(days: 90)),
    );
    await activate();
    await pumpNotice(tester);

    await tester.tap(find.text('Enter code'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Unlock Code'), findsOneWidget);
  });
}
