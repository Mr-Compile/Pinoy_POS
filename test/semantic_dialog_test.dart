import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

void main() {
  group('AppDialogType semantic mapping', () {
    test('icons map to the expected Material icons', () {
      expect(AppDialogType.success.icon, Icons.check_circle);
      expect(AppDialogType.error.icon, Icons.cancel);
      expect(AppDialogType.warning.icon, Icons.warning_amber_rounded);
      expect(AppDialogType.info.icon, Icons.info);
      expect(AppDialogType.delete.icon, Icons.delete_outline);
      expect(AppDialogType.permanentDelete.icon, Icons.warning_amber_rounded);
      expect(AppDialogType.restore.icon, Icons.restore);
      expect(AppDialogType.ai.icon, Icons.auto_awesome);
      expect(AppDialogType.logout.icon, Icons.logout);
      expect(AppDialogType.offline.icon, Icons.wifi_off);
      expect(AppDialogType.loading.icon, isNull);
    });

    test('icon container colours use the canonical semantic colours', () {
      const light = Brightness.light;
      const dark = Brightness.dark;

      expect(AppDialogType.success.iconBgColor(light), AppSemanticColors.success);
      expect(AppDialogType.error.iconBgColor(light), AppSemanticColors.error);
      expect(AppDialogType.warning.iconBgColor(light), AppSemanticColors.warning);
      expect(AppDialogType.info.iconBgColor(light), AppSemanticColors.info);
      expect(AppDialogType.delete.iconBgColor(light), AppSemanticColors.error);
      expect(AppDialogType.restore.iconBgColor(light), AppSemanticColors.success);
      expect(AppDialogType.ai.iconBgColor(light), AppSemanticColors.purple);
      expect(AppDialogType.logout.iconBgColor(light), AppSemanticColors.error);
      expect(AppDialogType.restriction.iconBgColor(light), AppSemanticColors.neutral);

      // Dark mode uses the same saturated canonical colours.
      expect(AppDialogType.success.iconBgColor(dark), AppSemanticColors.success);
      expect(AppDialogType.error.iconBgColor(dark), AppSemanticColors.error);

      // The icon symbol is always a light/white colour for contrast.
      for (final type in AppDialogType.values) {
        expect(type.iconColor(light), AppColorTokens.onPrimaryBlue);
        expect(type.iconColor(dark), AppColorTokens.onPrimaryBlue);
      }
    });

    test('primary button colours follow the design language', () {
      expect(AppDialogType.success.primaryButtonColor, AppButtonColor.success);
      expect(AppDialogType.error.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.warning.primaryButtonColor, AppButtonColor.warning);
      expect(AppDialogType.info.primaryButtonColor, AppButtonColor.primary);
      expect(AppDialogType.delete.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.permanentDelete.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.restore.primaryButtonColor, AppButtonColor.success);
      expect(AppDialogType.ai.primaryButtonColor, AppButtonColor.purple);
      expect(AppDialogType.logout.primaryButtonColor, AppButtonColor.error);
      expect(AppDialogType.restriction.primaryButtonColor, AppButtonColor.neutral);
      expect(AppDialogType.offline.primaryButtonColor, AppButtonColor.primary);
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

      final container = tester.widget<Container>(findIconContainer(Icons.check_circle));
      expect((container.decoration as BoxDecoration).color, AppSemanticColors.success);

      final bg = filledBackgroundColor('Done', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.successSurface,
        Brightness.light,
      ));
    });

    testWidgets('error dialog shows a red x icon and red button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.error,
          title: 'Failed',
          message: 'Request failed.',
          actions: const [AppDialogAction(label: 'OK', isPrimary: true)],
        ),
      );

      final container = tester.widget<Container>(findIconContainer(Icons.cancel));
      expect((container.decoration as BoxDecoration).color, AppSemanticColors.error);

      final bg = filledBackgroundColor('OK', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.errorSurface,
        Brightness.light,
      ));
    });

    testWidgets('delete dialog shows a trash icon and destructive red button', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.delete,
          title: 'Delete?',
          message: 'Delete this item?',
          actions: const [
            AppDialogAction(
              label: 'Delete',
              isPrimary: true,
              isDestructive: true,
            ),
          ],
        ),
      );

      expect(findIconContainer(Icons.delete_outline), findsOneWidget);

      final bg = filledBackgroundColor('Delete', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.errorSurface,
        Brightness.light,
      ));
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
      expect((container.decoration as BoxDecoration).color, AppSemanticColors.success);

      final bg = filledBackgroundColor('Restore', Brightness.light, tester);
      expect(bg, AppSemanticColors.resolveSurface(
        AppSemanticColors.successSurface,
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

    testWidgets('narrow dialog stacks buttons vertically', (tester) async {
      await pumpDialog(
        tester,
        AppDialog(
          type: AppDialogType.info,
          title: 'Confirm',
          message: 'Proceed?',
          actions: const [
            AppDialogAction(label: 'Cancel'),
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
