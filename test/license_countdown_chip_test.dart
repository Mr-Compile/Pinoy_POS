import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/widgets/license_countdown_chip.dart';

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

  Future<void> pumpChip(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [licenseServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(
          home: Scaffold(body: LicenseCountdownChip()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows a trial countdown for short terms', (tester) async {
    await service.saveConfig(
      armed: true,
      expiresAt: now.add(const Duration(days: 30)),
    );
    await pumpChip(tester);

    expect(find.text('Trial · 30 days left'), findsOneWidget);
    expect(find.text('Enter code'), findsOneWidget);
  });

  testWidgets('shows a license countdown for longer terms', (tester) async {
    await service.saveConfig(
      armed: true,
      expiresAt: now.add(const Duration(days: 90)),
    );
    await pumpChip(tester);

    expect(find.text('License · 90 days left'), findsOneWidget);
  });

  testWidgets('hands off to the warning banner inside the warning window',
      (tester) async {
    await service.saveConfig(
      armed: true,
      expiresAt: now.add(const Duration(days: 30)),
    );
    // 5 days remain — inside the proportional warning window.
    now = now.add(const Duration(days: 25));
    await pumpChip(tester);

    expect(tester.getSize(find.byType(LicenseCountdownChip)), Size.zero);
    expect(find.textContaining('days left'), findsNothing);
  });

  testWidgets('renders nothing when no license is configured',
      (tester) async {
    await pumpChip(tester);

    expect(tester.getSize(find.byType(LicenseCountdownChip)), Size.zero);
  });

  testWidgets('renders nothing when the license is disarmed', (tester) async {
    await service.saveConfig(armed: false);
    await pumpChip(tester);

    expect(tester.getSize(find.byType(LicenseCountdownChip)), Size.zero);
  });
}
