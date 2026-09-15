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
}
