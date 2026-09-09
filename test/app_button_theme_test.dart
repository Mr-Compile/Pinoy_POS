import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// Regression tests for the shared button theming system:
///
/// - The "Sign In" gradient button previously painted its label with
///   `ColorScheme.onSurface`, which is near-black in light mode and made
///   the label unreadable on the dark brand gradient.
/// - Filled semantic buttons now use [AppSemanticColors.resolveSurface] so
///   they render deep, intentional surfaces in dark mode with a
///   contrast-computed foreground instead of pale accent fills with black
///   text.
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

  group('AppButton.filled surfaces', () {
    final cases = <AppButtonColor, (Color, Color)>{
      AppButtonColor.success: (
        AppSemanticColors.successSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.successSurface,
          Brightness.dark,
        ),
      ),
      AppButtonColor.warning: (
        AppSemanticColors.warningSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.warningSurface,
          Brightness.dark,
        ),
      ),
      AppButtonColor.error: (
        AppSemanticColors.errorSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.errorSurface,
          Brightness.dark,
        ),
      ),
      AppButtonColor.info: (
        AppSemanticColors.infoSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.infoSurface,
          Brightness.dark,
        ),
      ),
      AppButtonColor.neutral: (
        AppSemanticColors.neutralSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.neutralSurface,
          Brightness.dark,
        ),
      ),
      AppButtonColor.purple: (
        AppSemanticColors.purpleSurface,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.purpleSurface,
          Brightness.dark,
        ),
      ),
    };

    for (final (name, theme, brightness) in [
      ('light', AppColors.getLightTheme(), Brightness.light),
      ('dark', AppColors.getDarkTheme(), Brightness.dark),
    ]) {
      for (final entry in cases.entries) {
        testWidgets(
            '${entry.key.name} filled button uses a surface in $name theme',
            (tester) async {
          await tester.pumpWidget(wrap(
            AppButton.filled(
              label: 'Action',
              color: entry.key,
              onPressed: () {},
            ),
            theme,
          ));

          final expectedBackground =
              AppSemanticColors.resolveSurface(entry.value.$1, brightness);
          final expectedForeground =
              AppSemanticColors.contrastFor(expectedBackground, brightness);

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
        });
      }
    }
  });
}
