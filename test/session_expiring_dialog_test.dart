import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/ui/dialogs/session_expiring_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_countdown_ring.dart';

final _fixedNow = DateTime(2026, 1, 1, 12, 0, 0);

Future<void> _openDialog(
  WidgetTester tester, {
  required DateTime deadline,
  Duration warningDuration = const Duration(seconds: 30),
  VoidCallback? onContinue,
  VoidCallback? onLogout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SessionExpiringDialog(
              deadline: deadline,
              warningDuration: warningDuration,
              onContinue: onContinue ?? () {},
              onLogout: onLogout ?? () {},
              clock: () => _fixedNow,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // A periodic ticker runs inside the dialog, so pumpAndSettle would never
  // settle — a single pump is enough to lay out the first frame.
  await tester.pump();
}

void main() {
  testWidgets('renders the countdown number inside a full ring', (tester) async {
    await _openDialog(
      tester,
      deadline: _fixedNow.add(const Duration(seconds: 30)),
    );

    expect(find.text('Session Expiring'), findsOneWidget);
    expect(find.text('Are you still there?'), findsOneWidget);
    expect(find.byType(AppCountdownRing), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('30 seconds'), findsOneWidget);
    expect(find.text('Continue Session'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);

    // 30s remaining of a 30s window -> the ring is full.
    final ring = tester.widget<AppCountdownRing>(
      find.byType(AppCountdownRing),
    );
    expect(ring.value, 1.0);
  });

  testWidgets('the ring reflects the remaining fraction of the window',
      (tester) async {
    await _openDialog(
      tester,
      deadline: _fixedNow.add(const Duration(seconds: 15)),
    );

    final ring = tester.widget<AppCountdownRing>(
      find.byType(AppCountdownRing),
    );
    expect(ring.value, 0.5);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('15 seconds'), findsOneWidget);
  });

  testWidgets('uses the singular "second" label when one second remains',
      (tester) async {
    await _openDialog(
      tester,
      deadline: _fixedNow.add(const Duration(milliseconds: 500)),
    );

    expect(find.text('1 second'), findsOneWidget);
  });

  testWidgets('Continue Session closes the dialog and invokes the callback',
      (tester) async {
    var continued = false;
    await _openDialog(
      tester,
      deadline: _fixedNow.add(const Duration(seconds: 30)),
      onContinue: () => continued = true,
    );

    await tester.tap(find.text('Continue Session'));
    await tester.pump();

    expect(continued, isTrue);
    expect(find.byType(SessionExpiringDialog), findsNothing);
  });

  testWidgets('Log Out closes the dialog and invokes the callback',
      (tester) async {
    var loggedOut = false;
    await _openDialog(
      tester,
      deadline: _fixedNow.add(const Duration(seconds: 30)),
      onLogout: () => loggedOut = true,
    );

    await tester.tap(find.text('Log Out'));
    await tester.pump();

    expect(loggedOut, isTrue);
    expect(find.byType(SessionExpiringDialog), findsNothing);
  });
}
