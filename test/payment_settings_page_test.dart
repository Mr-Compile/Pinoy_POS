import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/ui/screens/payment_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

class _FakeSettingsService extends SettingsService {
  Settings _settings;
  Settings? lastUpdated;

  _FakeSettingsService(this._settings);

  @override
  Future<Settings> getSettings() async => _settings;

  @override
  Future<bool> updateSettings(Settings settings) async {
    lastUpdated = settings;
    _settings = settings;
    return true;
  }

  @override
  Future<ImagePickResult> updateGcashQrImage() async =>
      ImagePickResult.success(
        'gcash_qr/test.png',
        mediaType: 'image/png',
      );

  @override
  Future<void> clearGcashQrImage() async {
    _settings = _settings.copyWith(
      gcashQrImagePath: null,
      gcashQrImageType: null,
    );
  }
}

void main() {
  setUp(() {
    SessionManager.resetForTest();
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  Future<void> pumpWithOwner(
    WidgetTester tester,
    _FakeSettingsService fakeService,
  ) async {
    final owner = User(
      id: 1,
      username: 'owner',
      passwordHash: 'test-hash',
      role: UserRole.owner,
      fullName: 'Store Owner',
      createdAt: DateTime.now(),
    );
    SessionManager().setCurrentUser(owner);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => fakeService),
        ],
        child: const MaterialApp(
          home: PaymentSettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('PaymentSettingsPage builds and removes admin verifier',
      (tester) async {
    final settings = Settings(
      storeName: 'Test Store',
      gcashEnabled: true,
      gcashReferenceRequired: true,
      gcashCustomerNameRequirement: 'optional',
      gcashPaymentProofRequirement: 'optional',
      gcashVerificationMode: 'owner',
      gcashReferenceMinLength: 6,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final fakeService = _FakeSettingsService(settings);
    await pumpWithOwner(tester, fakeService);

    expect(find.text('Payment Settings'), findsWidgets);
    expect(find.text('GCash'), findsWidgets);
    expect(find.text('Verify staff GCash sales'), findsOneWidget);
    expect(find.text('Who can verify'), findsNothing);
    expect(find.text('Owner or System Admin'), findsNothing);
  });

  testWidgets('PaymentSettingsPage saves verification as owner only',
      (tester) async {
    final settings = Settings(
      storeName: 'Test Store',
      gcashEnabled: true,
      gcashReferenceRequired: true,
      gcashCustomerNameRequirement: 'optional',
      gcashPaymentProofRequirement: 'optional',
      gcashVerificationMode: 'immediate',
      gcashReferenceMinLength: 6,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final fakeService = _FakeSettingsService(settings);
    await pumpWithOwner(tester, fakeService);

    // Toggle verification on.
    final verifySwitchFinder = find.descendant(
      of: find.widgetWithText(ListTile, 'Verify staff GCash sales'),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(verifySwitchFinder);
    await tester.tap(verifySwitchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Save.
    final saveFinder = find.widgetWithText(AppButton, 'Save Payment Settings');
    await tester.ensureVisible(saveFinder);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(saveFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeService.lastUpdated, isNotNull);
    expect(fakeService.lastUpdated!.gcashVerificationMode, 'owner');
  });
}
