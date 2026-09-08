import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/quick_action_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_quick_action_card.dart';
import 'package:pinoy_pos/ui/widgets/quick_action_grid.dart';

/// Regression tests for the shared button theming and quick action color
/// system:
///
/// - The "Sign In" gradient button previously painted its label with
///   `ColorScheme.onSurface`, which is near-black in light mode and made
///   the label unreadable on the dark brand gradient.
/// - Filled semantic buttons now use [AppSemanticColors.resolveSurface] so
///   they render deep, intentional surfaces in dark mode with a
///   contrast-computed foreground instead of pale accent fills with black
///   text.
/// - Quick actions resolve their colors through [QuickActionType] and the
///   centralized [resolveQuickActionStyle] so every role sees the same
///   semantic colors with correct light/dark foregrounds.
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

  group('QuickActionTheme resolves theme-aware styles', () {
    test('light mode trash is amber with dark foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.light,
        QuickActionType.trash,
      );
      expect(style.background, AppSemanticColors.warningSurface);
      expect(
        style.foreground,
        AppSemanticColors.contrastFor(
          AppSemanticColors.warningSurface,
          Brightness.light,
        ),
      );
    });

    test('dark mode trash is deep amber with light foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.trash,
      );
      expect(
        style.background,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.warningSurface,
          Brightness.dark,
        ),
      );
      expect(style.foreground, AppColorTokens.textPrimary);
    });

    test('dark mode manage users uses primary blue with light foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.manageUsers,
      );
      expect(
        style.background,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.primarySurface,
          Brightness.dark,
        ),
      );
      expect(style.foreground, AppColorTokens.textPrimary);
    });

    test('dark mode activity logs uses neutral surface with light foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.activityLogs,
      );
      expect(
        style.background,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.neutralSurface,
          Brightness.dark,
        ),
      );
      expect(style.foreground, AppColorTokens.textPrimary);
    });

    test('dark mode ai config uses info surface with light foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.aiConfig,
      );
      expect(
        style.background,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.infoSurface,
          Brightness.dark,
        ),
      );
      expect(style.foreground, AppColorTokens.textPrimary);
    });

    test('dark mode settings uses neutral surface with light foreground', () {
      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.settings,
      );
      expect(
        style.background,
        AppSemanticColors.resolveSurface(
          AppSemanticColors.neutralSurface,
          Brightness.dark,
        ),
      );
      expect(style.foreground, AppColorTokens.textPrimary);
    });
  });

  group('AppQuickActionCard rendering', () {
    testWidgets('Trash action renders the resolved background and foreground',
        (tester) async {
      await tester.pumpWidget(wrap(
        const AppQuickActionCard(
          type: QuickActionType.trash,
          onTap: null,
        ),
        AppColors.getDarkTheme(),
      ));

      final style = resolveQuickActionStyleForBrightness(
        Brightness.dark,
        QuickActionType.trash,
      );

      final container = tester.widget<Material>(
        find.descendant(
          of: find.byType(AppQuickActionCard),
          matching: find.byType(Material),
        ),
      );
      expect(container.color, style.background);

      final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
      expect(icon.color, style.foreground);

      final label = tester.widget<Text>(find.text('Trash'));
      expect(label.style?.color, style.foreground);
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
