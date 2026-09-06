import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/quick_action_grid.dart';

/// Regression tests for the shared button theming:
///
/// - The "Sign In" gradient button previously painted its label with
///   `ColorScheme.onSurface`, which is near-black in light mode and made
///   the label unreadable on the dark brand gradient.
/// - Quick actions painted `ColorScheme.onSurface` on top of semantic
///   fills, producing dark text on dark fills in light mode and white
///   text on lightened fills in dark mode. They must use the semantic
///   role's paired "on" color in both themes.
void main() {
  Widget wrap(Widget child, ThemeData theme) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('AppButton.gradient label color', () {
    for (final (name, theme) in [
      ('light', AppColors.getLightTheme()),
      ('dark', AppColors.getDarkTheme()),
    ]) {
      testWidgets('Sign In label stays white in $name theme',
          (tester) async {
        await tester.pumpWidget(wrap(
          AppButton.gradient(label: 'Sign In', onPressed: () {}),
          theme,
        ));

        final label = tester.widget<Text>(find.text('Sign In'));
        expect(label.style?.color, AppSemanticColors.onPrimary);
      });
    }
  });

  group('AppButton.quickAction foreground', () {
    final cases = <AppButtonColor, (Color, Color)>{
      AppButtonColor.success: (
        AppSemanticColors.success,
        AppSemanticColors.onSuccess,
      ),
      AppButtonColor.warning: (
        AppSemanticColors.warning,
        AppSemanticColors.onWarning,
      ),
      AppButtonColor.error: (
        AppSemanticColors.error,
        AppSemanticColors.onError,
      ),
      AppButtonColor.info: (
        AppSemanticColors.info,
        AppSemanticColors.onInfo,
      ),
      AppButtonColor.neutral: (
        AppSemanticColors.neutral,
        AppSemanticColors.onNeutral,
      ),
    };

    for (final (name, theme, brightness) in [
      ('light', AppColors.getLightTheme(), Brightness.light),
      ('dark', AppColors.getDarkTheme(), Brightness.dark),
    ]) {
      for (final entry in cases.entries) {
        testWidgets(
            '${entry.key.name} uses its semantic on-color in $name theme',
            (tester) async {
          await tester.pumpWidget(wrap(
            AppButton.quickAction(
              icon: Icons.star,
              label: 'Action',
              color: entry.key,
              onPressed: () {},
            ),
            theme,
          ));

          final expectedForeground = AppSemanticColors.resolveOn(
            entry.value.$2,
            brightness,
          );
          final expectedBackground = AppSemanticColors.resolve(
            entry.value.$1,
            brightness,
          );

          final button = tester.widget<FilledButton>(
            find.byType(FilledButton),
          );
          final style = button.style!;

          expect(
            style.backgroundColor?.resolve({WidgetState.focused}),
            expectedBackground,
          );
          expect(
            style.foregroundColor?.resolve({WidgetState.focused}),
            expectedForeground,
          );
          // The foreground must never be the surface text color — that was
          // the contrast bug this regression test guards.
          expect(
            style.foregroundColor?.resolve({WidgetState.focused}),
            isNot(theme.colorScheme.onSurface),
          );
        });
      }
    }

    testWidgets('disabled quick action is dimmed on the semantic fill',
        (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton.quickAction(
          icon: Icons.star,
          label: 'Action',
          color: AppButtonColor.success,
          onPressed: null,
        ),
        AppColors.getLightTheme(),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final style = button.style!;
      expect(
        style.backgroundColor?.resolve({WidgetState.disabled}),
        AppSemanticColors.success.withValues(alpha: 0.12),
      );
      expect(
        style.foregroundColor?.resolve({WidgetState.disabled}),
        AppSemanticColors.onSuccess.withValues(alpha: 0.38),
      );
    });
  });

  group('QuickActionGrid responsiveness', () {
    for (final (name, width, expectedColumns) in [
      ('phone portrait', 400.0, 2),
      ('tablet', 700.0, 3),
      ('desktop/web', 1100.0, 4),
    ]) {
      testWidgets('$name renders $expectedColumns columns', (tester) async {
        // The grid adapts to its layout constraints, which are bounded by
        // the viewport — so the test surface itself must be resized.
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(wrap(
          QuickActionGrid(
            children: List.generate(6, (i) => Text('A$i')),
          ),
          AppColors.getLightTheme(),
        ));

        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, expectedColumns);
      });
    }
  });
}
