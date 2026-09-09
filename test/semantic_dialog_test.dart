import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

void main() {
  group('AppDialogType semantic mapping', () {
    test('icons map to the expected Material icons', () {
      expect(AppDialogType.success.icon, Icons.check_circle_outline);
      expect(AppDialogType.error.icon, Icons.cancel_outlined);
      expect(AppDialogType.validation.icon, Icons.cancel_outlined);
      expect(AppDialogType.warning.icon, Icons.warning_amber_outlined);
      expect(AppDialogType.info.icon, Icons.info_outline);
      expect(AppDialogType.delete.icon, Icons.delete_outline);
      expect(AppDialogType.permanentDelete.icon, Icons.delete_forever);
      expect(AppDialogType.restore.icon, Icons.restore);
      expect(AppDialogType.ai.icon, Icons.auto_awesome);
      expect(AppDialogType.logout.icon, Icons.logout);
      expect(AppDialogType.offline.icon, Icons.wifi_off);
      expect(AppDialogType.confirmation.icon, Icons.help_outline);
      expect(AppDialogType.payment.icon, Icons.account_balance_wallet_outlined);
      expect(AppDialogType.loading.icon, isNull);
    });

    test('icon container colours are 16% alpha of the semantic icon colour', () {
      const light = Brightness.light;
      const dark = Brightness.dark;

      for (final type in AppDialogType.values) {
        final iconColor = type.iconColor(light);
        final containerColor = type.iconBgColor(light);
        expect(
          containerColor,
          iconColor.withValues(alpha: 0.16),
          reason: '$type light container should be 16% of its icon color',
        );
      }

      for (final type in AppDialogType.values) {
        final iconColor = type.iconColor(dark);
        final containerColor = type.iconBgColor(dark);
        expect(
          containerColor,
          iconColor.withValues(alpha: 0.16),
          reason: '$type dark container should be 16% of its icon color',
        );
      }

      // The icon symbol uses the semantic colour itself.
      expect(
        AppDialogType.success.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.success, light),
      );
      expect(
        AppDialogType.error.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.error, light),
      );
      expect(
        AppDialogType.warning.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.warning, light),
      );
      expect(
        AppDialogType.info.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.info, light),
      );
      expect(
        AppDialogType.delete.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.error, light),
      );
      expect(
        AppDialogType.ai.iconColor(light),
        AppSemanticColors.resolve(AppSemanticColors.violet, light),
      );
    });

    test('primary button colours follow the design language', () {
      expect(AppDialogType.success.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.error.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.validation.primaryButtonColor, AppButtonColor.warning);
      expect(AppDialogType.warning.primaryButtonColor, AppButtonColor.warning);
      expect(AppDialogType.info.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.delete.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.permanentDelete.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.restore.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.ai.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.logout.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.restriction.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.offline.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.confirmation.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.payment.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.add.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.edit.primaryButtonColor, AppButtonColor.primary);
    });
  });

  group('AppDialog renders the correct semantic visuals', () {
    Future<void> pumpDialog(
      WidgetTester tester,
      AppDialog dialog, {
      Size viewSize = const Size(400, 600),
    }) async {
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => dialog,
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
    }

    Finder findIconContainer(IconData icon) {
      return find.descendant(
        of: find.byType(AppDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.child is Icon &&
              (w.child as Icon).icon == icon &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
    }

    Color filledBackgroundColor(String label, Brightness brightness, WidgetTester tester) {
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
        ),
      );
      return button.style!.backgroundColor!.resolve({
        if (brightness == Brightness.dark) WidgetState.hovered,
      })!;
    }

    testWidgets('success dialog shows a green check icon and green button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.success,
          title: 'Saved',
          message: 'Item saved.',
          actions: const [AppDialogAction(label: 'Done', isPrimary: true)],
        ),
      );

      final container = tester.widget<Container>(findIconContainer(Icons.check_circle_outline));
      expect(
        (container.decoration as BoxDecoration).color,
        AppDialogType.success.iconColor(Brightness.light).withValues(alpha: 0.16),
      );

      final bg = filledBackgroundColor('Done', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.primarySurface,
        Brightness.light,
      ));
    });

    testWidgets('error dialog shows a red x icon and primary action button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.error,
          title: 'Failed',
          message: 'Request failed.',
          actions: const [AppDialogAction(label: 'Close', isPrimary: true)],
        ),
      );

      final container = tester.widget<Container>(findIconContainer(Icons.cancel_outlined));
      expect(
        (container.decoration as BoxDecoration).color,
        AppDialogType.error.iconColor(Brightness.light).withValues(alpha: 0.16),
      );

      final bg = filledBackgroundColor('Close', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.primarySurface,
        Brightness.light,
      ));
    });

    testWidgets('delete dialog shows a trash icon and outlined red primary button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.delete,
          title: 'Delete?',
          message: 'Delete this item?',
          actions: const [
            AppDialogAction(label: 'Cancel'),
            AppDialogAction(
              label: 'Delete',
              isPrimary: true,
              isDestructive: true,
            ),
          ],
        ),
      );

      expect(findIconContainer(Icons.delete_outline), findsOneWidget);

      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.ancestor(
            of: find.text('Delete'),
            matching: find.byType(OutlinedButton),
          ),
        ),
      );
      final fg = button.style!.foregroundColor!.resolve({});
      expect(fg, AppSemanticColors.resolve(AppSemanticColors.error, Brightness.light));
    });

    testWidgets('restore dialog shows a restore icon and green button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.restore,
          title: 'Restore?',
          message: 'Restore this item?',
          actions: const [AppDialogAction(label: 'Restore', isPrimary: true)],
        ),
      );

      final container = tester.widget<Container>(findIconContainer(Icons.restore));
      expect(
        (container.decoration as BoxDecoration).color,
        AppDialogType.restore.iconColor(Brightness.light).withValues(alpha: 0.16),
      );

      final bg = filledBackgroundColor('Restore', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.primarySurface,
        Brightness.light,
      ));
    });

    testWidgets('action color overrides the type default', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.error,
          title: 'Refresh Failed',
          message: 'Could not refresh.',
          actions: const [
            AppDialogAction(
              label: 'Try Again',
              isPrimary: true,
              color: AppButtonColor.primary,
            ),
          ],
        ),
      );

      final bg = filledBackgroundColor('Try Again', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.primarySurface,
        Brightness.light,
      ));
    });

    testWidgets('secondary destructive action uses an outlined red button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.warning,
          title: 'Session Expiring',
          message: 'Are you still there?',
          actions: const [
            AppDialogAction(label: 'Log Out', color: AppButtonColor.error),
            AppDialogAction(
              label: 'Continue',
              isPrimary: true,
              color: AppButtonColor.success,
            ),
          ],
        ),
      );

      expect(
        find.descendant(of: find.byType(AppDialog), matching: find.byType(OutlinedButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppDialog), matching: find.byType(FilledButton)),
        findsOneWidget,
      );

      final outlined = tester.widget<OutlinedButton>(
        find.descendant(of: find.byType(AppDialog), matching: find.byType(OutlinedButton)),
      );
      final fg = outlined.style!.foregroundColor!.resolve({});
      expect(fg, AppSemanticColors.resolve(
        AppSemanticColors.error,
        Brightness.light,
      ));
    });

    testWidgets('narrow dialog with more than two actions stacks buttons vertically', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.info,
          title: 'Confirm',
          message: 'Proceed?',
          actions: const [
            AppDialogAction(label: 'Cancel'),
            AppDialogAction(label: 'Keep'),
            AppDialogAction(label: 'OK', isPrimary: true),
          ],
        ),
        viewSize: const Size(320, 600),
      );

      final cancelRect = tester.getRect(find.text('Cancel'));
      final okRect = tester.getRect(find.text('OK'));
      expect(cancelRect.top, lessThan(okRect.top));
    });

    testWidgets('long message wraps without clipping', (tester) async {
      const longMessage =
          'This is a very long message that should wrap across multiple lines in the dialog and remain fully readable.';
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.info,
          title: 'Notice',
          message: longMessage,
          actions: const [AppDialogAction(label: 'OK', isPrimary: true)],
        ),
      );

      expect(find.text(longMessage), findsOneWidget);
    });
  });
}
