import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';

void main() {
  group('AppDialogForm', () {
    testWidgets('returns cancelled when cancel is pressed', (tester) async {
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
                      useRootNavigator: true,
                      builder: (_) => AppDialogForm<ModalResult<String>>(
                        type: AppDialogType.info,
                        title: 'Edit',
                        childBuilder: (context, state) => TextFormField(
                          controller: state.textController('value'),
                          decoration: const InputDecoration(labelText: 'Value'),
                        ),
                        actionsBuilder: (context, state) => [
                          AppDialogAction(
                            label: 'Cancel',
                            onPressed: (_) => state.pop(
                              const ModalResult<String>.cancelled(),
                            ),
                          ),
                          AppDialogAction(
                            label: 'Save',
                            isPrimary: true,
                            onPressed: (_) => state.pop(
                              ModalResult<String>.saved(
                                state.textController('value').text.trim(),
                              ),
                            ),
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
    });

    testWidgets('returns saved value when save is pressed', (tester) async {
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
                      useRootNavigator: true,
                      builder: (_) => AppDialogForm<ModalResult<String>>(
                        type: AppDialogType.info,
                        title: 'Edit',
                        childBuilder: (context, state) => TextFormField(
                          controller: state.textController('value'),
                          decoration: const InputDecoration(labelText: 'Value'),
                        ),
                        actionsBuilder: (context, state) => [
                          AppDialogAction(
                            label: 'Cancel',
                            onPressed: (_) => state.pop(
                              const ModalResult<String>.cancelled(),
                            ),
                          ),
                          AppDialogAction(
                            label: 'Save',
                            isPrimary: true,
                            onPressed: (_) => state.pop(
                              ModalResult<String>.saved(
                                state.textController('value').text.trim(),
                              ),
                            ),
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

      await tester.enterText(find.byType(TextFormField), 'hello');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isSaved, isTrue);
      expect(result!.value, 'hello');
    });

    testWidgets('dismissing the barrier returns null', (tester) async {
      ModalResult<String>? result = const ModalResult<String>.saved('initial');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<ModalResult<String>>(
                      context: context,
                      barrierDismissible: true,
                      useRootNavigator: true,
                      builder: (_) => AppDialogForm<ModalResult<String>>(
                        type: AppDialogType.info,
                        title: 'Edit',
                        childBuilder: (context, state) => TextFormField(
                          controller: state.textController('value'),
                          decoration: const InputDecoration(labelText: 'Value'),
                        ),
                        actionsBuilder: (context, state) => [
                          AppDialogAction(
                            label: 'Cancel',
                            onPressed: (_) => state.pop(
                              const ModalResult<String>.cancelled(),
                            ),
                          ),
                          AppDialogAction(
                            label: 'Save',
                            isPrimary: true,
                            onPressed: (_) => state.pop(
                              ModalResult<String>.saved(
                                state.textController('value').text.trim(),
                              ),
                            ),
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

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('keeps actions visible and scrolls long forms under keyboard insets',
        (tester) async {
      const screenSize = Size(400, 600);
      const keyboardInset = 180.0;

      tester.view.physicalSize = screenSize;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardInset);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<ModalResult<String>>(
                    context: context,
                    barrierDismissible: false,
                    useRootNavigator: true,
                    builder: (_) => AppDialogForm<ModalResult<String>>(
                      type: AppDialogType.info,
                      title: 'Long Form',
                      childBuilder: (context, state) => Column(
                        children: [
                          for (var i = 0; i < 12; i++)
                            TextFormField(
                              controller: state.textController('field_$i'),
                              showCursor: false,
                              decoration: InputDecoration(
                                labelText: 'Field ${i + 1}',
                              ),
                            ),
                        ],
                      ),
                      actionsBuilder: (context, state) => [
                        AppDialogAction(
                          label: 'Cancel',
                          onPressed: (_) => state.pop(
                            const ModalResult<String>.cancelled(),
                          ),
                        ),
                        AppDialogAction(
                          label: 'Save',
                          isPrimary: true,
                          onPressed: (_) => state.pop(
                            ModalResult<String>.saved('ok'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The form is inside a scrollable region.
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // The action buttons are rendered and remain accessible.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Both actions sit above the simulated keyboard area.
      final saveRect = tester.getRect(find.text('Save'));
      final cancelRect = tester.getRect(find.text('Cancel'));
      expect(saveRect.bottom, lessThan(screenSize.height - keyboardInset));
      expect(cancelRect.bottom, lessThan(screenSize.height - keyboardInset));
    });
  });
}
