import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/ui/widgets/sales_trend_chart.dart';

void main() {
  testWidgets('SalesTrendChart shows empty state when all points are zero',
      (tester) async {
    final trend = [
      DailySalesPoint(date: DateTime(2026, 9, 1), total: 0.0, count: 0),
      DailySalesPoint(date: DateTime(2026, 9, 2), total: 0.0, count: 0),
      DailySalesPoint(date: DateTime(2026, 9, 3), total: 0.0, count: 0),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrendChart(
            trend: trend,
            groupBy: ReportGroupBy.day,
          ),
        ),
      ),
    );

    expect(find.text('No trend data'), findsOneWidget);
    expect(find.text('There are no sales to display for this period.'),
        findsOneWidget);
  });

  testWidgets('SalesTrendChart shows empty state when trend is empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrendChart(
            trend: const [],
            groupBy: ReportGroupBy.day,
          ),
        ),
      ),
    );

    expect(find.text('No trend data'), findsOneWidget);
  });

  testWidgets('SalesTrendChart renders chart when there is at least one non-zero point',
      (tester) async {
    final trend = [
      DailySalesPoint(date: DateTime(2026, 9, 1), total: 0.0, count: 0),
      DailySalesPoint(date: DateTime(2026, 9, 2), total: 100.0, count: 1),
      DailySalesPoint(date: DateTime(2026, 9, 3), total: 0.0, count: 0),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrendChart(
            trend: trend,
            groupBy: ReportGroupBy.day,
          ),
        ),
      ),
    );

    expect(find.text('No trend data'), findsNothing);
  });

  testWidgets('SalesTrendChart scrollable bar chart does not crash with unbounded height',
      (tester) async {
    final trend = List.generate(
      15,
      (i) => DailySalesPoint(
        date: DateTime(2026, 9, 1).add(Duration(days: i)),
        total: (i + 1) * 10.0,
        count: i + 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SalesTrendChart(
              trend: trend,
              groupBy: ReportGroupBy.day,
            ),
          ),
        ),
      ),
    );

    expect(find.text('No trend data'), findsNothing);
    expect(find.text('150'), findsOneWidget);
  });
}
