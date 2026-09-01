import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/modal_result.dart';

void main() {
  group('ModalResult', () {
    test('saved carries a value and reports success', () {
      const result = ModalResult<int>.saved(42);

      expect(result.isSaved, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.isCancelled, isFalse);
      expect(result.isFailed, isFalse);
      expect(result.value, 42);
      expect(result.error, isNull);
    });

    test('confirmed is a success with no value', () {
      const result = ModalResult<void>.confirmed();

      expect(result.isConfirmed, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.isSaved, isFalse);
    });

    test('cancelled and dismissed are not failures', () {
      const cancelled = ModalResult<void>.cancelled();
      const dismissed = ModalResult<void>.dismissed();

      expect(cancelled.isCancelled, isTrue);
      expect(dismissed.isCancelled, isTrue);
      expect(cancelled.isFailed, isFalse);
      expect(dismissed.isFailed, isFalse);
      expect(cancelled.isSuccess, isFalse);
      expect(dismissed.isSuccess, isFalse);
      expect(cancelled.isDismissed, isFalse);
      expect(dismissed.isDismissed, isTrue);
    });

    test('failed carries error and cause', () {
      const result = ModalResult<int>.failed(error: 'bad', cause: 'x');

      expect(result.isFailed, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.isCancelled, isFalse);
      expect(result.error, 'bad');
      expect(result.cause, 'x');
      expect(result.value, isNull);
    });

    test('when selects the correct branch', () {
      const saved = ModalResult<int>.saved(7);
      final fromSaved = saved.when(
        saved: (v) => 's:$v',
        confirmed: () => 'c',
        cancelled: () => 'x',
        dismissed: () => 'd',
        failed: (e, c) => 'f:$e',
      );
      expect(fromSaved, 's:7');

      const failed = ModalResult<int>.failed(error: 'e');
      final fromFailed = failed.when(
        saved: (v) => 's',
        confirmed: () => 'c',
        cancelled: () => 'x',
        dismissed: () => 'd',
        failed: (e, c) => 'f:$e',
      );
      expect(fromFailed, 'f:e');
    });

    test('whenOrDefault provides a fallback', () {
      const cancelled = ModalResult<int>.cancelled();
      final value = cancelled.whenOrDefault<int>(
        saved: (v) => v! + 1,
        orDefault: () => -1,
      );
      expect(value, -1);
    });
  });

  group('ModalDialog with ModalResult', () {
    testWidgets('dialog returns cancelled when the cancel button is pressed',
        (tester) async {
      ModalResult<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<ModalResult<String>>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        title: const Text('Edit'),
                        content: const TextField(),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(
                              const ModalResult<String>.cancelled(),
                            ),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(
                              const ModalResult<String>.saved('value'),
                            ),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCancelled, isTrue);
      expect(result!.isSaved, isFalse);
      expect(result!.isFailed, isFalse);
    });

    testWidgets('dialog returns saved with a value when save is pressed',
        (tester) async {
      ModalResult<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<ModalResult<String>>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        title: const Text('Edit'),
                        content: const TextField(),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(
                              const ModalResult<String>.cancelled(),
                            ),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(
                              const ModalResult<String>.saved('value'),
                            ),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isSaved, isTrue);
      expect(result!.value, 'value');
    });

    testWidgets('dismissing the barrier is treated as cancellation',
        (tester) async {
      ModalResult<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<ModalResult<String>>(
                      context: context,
                      builder: (context) => const AlertDialog(
                        title: Text('Edit'),
                        content: Text('Tap outside to cancel'),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
