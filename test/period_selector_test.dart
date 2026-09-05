import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';

void main() {
  Widget wrap(
    Widget child, {
    double? width,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: width == null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              )
            : SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
      ),
    );
  }

  testWidgets('renders period dropdown and custom button', (tester) async {
    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.thisMonth,
          onSelected: (_) {},
          onCustomRange: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Period'), findsWidgets);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.date_range), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('selecting a preset calls onSelected', (tester) async {
    ReportingPeriod? result;

    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.thisMonth,
          onSelected: (p) => result = p,
          onCustomRange: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<ReportingPeriod>));
    await tester.pump();
    await tester.tap(find.text('This Week').last);
    await tester.pump();

    expect(result, ReportingPeriod.thisWeek);
  });

  testWidgets('non-curated selected value renders without failing',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.last30Days,
          onSelected: (_) {},
          onCustomRange: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Last 30 Days'), findsOneWidget);
  });

  testWidgets('custom button is disabled when onCustomRange is null',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.thisMonth,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('compact layout stacks dropdown above button', (tester) async {
    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.thisMonth,
          onSelected: (_) {},
          onCustomRange: (_) {},
        ),
        width: 320,
      ),
    );
    await tester.pump();

    final dropdownTop = tester.getTopLeft(
      find.byType(DropdownButton<ReportingPeriod>),
    );
    final buttonTop = tester.getTopLeft(find.byType(AppButton));

    expect(buttonTop.dy, greaterThan(dropdownTop.dy));
  });

  testWidgets('wide layout places button to the right of dropdown',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        PeriodSelector(
          selected: ReportingPeriod.thisMonth,
          onSelected: (_) {},
          onCustomRange: (_) {},
        ),
        width: 600,
      ),
    );
    await tester.pump();

    final dropdownTop = tester.getTopLeft(
      find.byType(DropdownButton<ReportingPeriod>),
    );
    final buttonTop = tester.getTopLeft(find.byType(AppButton));

    expect(buttonTop.dx, greaterThan(dropdownTop.dx));
  });
}
