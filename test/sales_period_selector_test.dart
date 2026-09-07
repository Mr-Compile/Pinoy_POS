import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/ui/widgets/sales_period_selector.dart';

void main() {
  testWidgets('SalesPeriodSelector renders custom mode', (tester) async {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 30));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesPeriodFilterProvider.overrideWith((ref) {
            return SalesPeriodFilterNotifier()..setCustomRange(start, today);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SalesPeriodSelector(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Choose date range'), findsOneWidget);
  });
}
