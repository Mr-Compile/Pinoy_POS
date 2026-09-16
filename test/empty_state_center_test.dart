import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/ui/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState centers horizontally in phone-portrait Scaffold body',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: EmptyState(
            icon: Icons.notifications_none,
            title: 'No Notifications',
            message: "You're all caught up!",
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(find.byIcon(Icons.notifications_none));
    final titleCenter = tester.getCenter(find.text('No Notifications'));
    debugPrint('iconCenter=$iconCenter titleCenter=$titleCenter');
    expect(iconCenter.dx, closeTo(180, 2));
    expect(titleCenter.dx, closeTo(180, 2));
  });

  // Regression: content shorter than the viewport width used to shrink-wrap
  // inside SingleChildScrollView and park at the left edge.
  testWidgets('EmptyState centers horizontally with short text', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.history,
            title: 'Empty',
            message: 'None yet.',
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(find.byIcon(Icons.history));
    final titleCenter = tester.getCenter(find.text('Empty'));
    debugPrint('iconCenter=$iconCenter titleCenter=$titleCenter');
    expect(iconCenter.dx, closeTo(206, 2));
    expect(titleCenter.dx, closeTo(206, 2));
  });

  // Regression: the filtered-empty branches nest EmptyState inside
  // Column(crossAxisAlignment: start) + Expanded (activity logs screen).
  testWidgets('EmptyState centers inside a left-aligned Column', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 40),
              Expanded(
                child: EmptyState(
                  icon: Icons.filter_alt_off,
                  title: 'No matching logs',
                  message: 'Try a different filter.',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(find.byIcon(Icons.filter_alt_off));
    debugPrint('iconCenter=$iconCenter');
    expect(iconCenter.dx, closeTo(206, 2));
  });
}
