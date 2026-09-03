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
  });
}
