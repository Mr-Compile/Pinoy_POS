import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';

class _FakeSalesService extends SalesService {
  final List<Sale> _sales;

  _FakeSalesService(this._sales);

  @override
  Future<List<Sale>> getFilteredSales({
    DateTime? start,
    DateTime? end,
    String? paymentMethod,
    String? paymentStatus,
    String? search,
    int? userId,
    int? limit = 500,
  }) async {
    return _sales;
  }
}

void main() {
  final fakeUser = User(
    id: 1,
    username: 'owner',
    passwordHash: 'hash',
    role: UserRole.owner,
    fullName: 'Owner User',
    createdAt: DateTime(2026, 1, 1),
  );

  final sampleSale = Sale(
    id: 1,
    totalAmount: 150.0,
    cashReceived: 150.0,
    change: 0.0,
    paymentMethod: 'Cash',
    paymentStatus: 'confirmed',
    userId: 1,
    createdAt: DateTime.now(),
    receiptNumber: 'SALE-001',
  );

  setUp(() {
    SessionManager.resetForTest();
    SessionManager().setCurrentUser(fakeUser);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  testWidgets(
      'SalesScreen renders and remains scrollable with keyboard insets',
      (tester) async {
    // Simulate a mobile portrait screen with the keyboard open.
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesServiceProvider.overrideWith(
            (ref) => _FakeSalesService([sampleSale]),
          ),
        ],
        child: const MaterialApp(
          home: SalesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // The screen must use a scrollable body so the fixed header + summary
    // never overflow when the viewport is shortened by the keyboard.
    expect(find.byType(CustomScrollView), findsOneWidget);

    // Header and search field remain accessible.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search receipt, customer, or reference...'), findsOneWidget);

    // Sale content is still rendered and scrollable.
    expect(find.text('Sale #SALE-001'), findsOneWidget);
    expect(find.text('Total Sales'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('SalesScreen empty state renders with keyboard insets',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesServiceProvider.overrideWith(
            (ref) => _FakeSalesService([]),
          ),
        ],
        child: const MaterialApp(
          home: SalesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.text('No Sales'), findsOneWidget);
    expect(find.text('Start selling to see sales history'), findsOneWidget);
  });
}
