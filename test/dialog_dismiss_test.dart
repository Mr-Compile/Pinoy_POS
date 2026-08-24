import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

void main() {
  testWidgets('AppDialogService.success OK button dismisses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => AppDialogService.success(
                  context,
                  title: 'Saved',
                  message: 'Test success.',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Test success.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsNothing);
    expect(find.text('Test success.'), findsNothing);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('AppDialogService.error Close button dismisses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => AppDialogService.error(
                  context,
                  title: 'Failed',
                  message: 'Test error.',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Test error.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsNothing);
    expect(find.text('Test error.'), findsNothing);
  });

  testWidgets('AppDialogService.confirmation Confirm/Cancel dismiss',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => AppDialogService.confirmation(
                  context,
                  title: 'Confirm?',
                  message: 'Test confirm.',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm?'), findsNothing);
  });
}
