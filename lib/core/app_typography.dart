import 'package:flutter/material.dart';

/// Centralized typography helpers for the Inter type scale.
///
/// Use these instead of ad-hoc `copyWith(fontWeight: ...)` calls so the
/// app keeps a single, predictable type hierarchy across screens.
class AppTypography {
  AppTypography._();

  static const String _fontFamily = 'Inter';

  static TextStyle _fallback({
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: _fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );

  static TextStyle displayLarge(BuildContext context) =>
      Theme.of(context).textTheme.displayLarge ?? _fallback(fontSize: 57);

  static TextStyle displayMedium(BuildContext context) =>
      Theme.of(context).textTheme.displayMedium ?? _fallback(fontSize: 45);

  static TextStyle displaySmall(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall ?? _fallback(fontSize: 36);

  static TextStyle headlineLarge(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge ?? _fallback(fontSize: 32);

  static TextStyle headlineMedium(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium ?? _fallback(fontSize: 28);

  static TextStyle headlineSmall(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall ?? _fallback(fontSize: 24);

  static TextStyle headlineSmallBold(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall ?? _fallback(fontSize: 24))
          .copyWith(fontWeight: FontWeight.bold);

  static TextStyle headlineSmallSemibold(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall ?? _fallback(fontSize: 24))
          .copyWith(fontWeight: FontWeight.w600);

  static TextStyle titleLarge(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge ?? _fallback(fontSize: 22);

  static TextStyle titleLargeBold(BuildContext context) =>
      (Theme.of(context).textTheme.titleLarge ?? _fallback(fontSize: 22))
          .copyWith(fontWeight: FontWeight.bold);

  static TextStyle titleMedium(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium ?? _fallback(fontSize: 16);

  static TextStyle titleMediumBold(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? _fallback(fontSize: 16))
          .copyWith(fontWeight: FontWeight.bold);

  static TextStyle titleMediumSemibold(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? _fallback(fontSize: 16))
          .copyWith(fontWeight: FontWeight.w600);

  static TextStyle titleSmall(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall ?? _fallback(fontSize: 14);

  static TextStyle titleSmallBold(BuildContext context) =>
      (Theme.of(context).textTheme.titleSmall ?? _fallback(fontSize: 14))
          .copyWith(fontWeight: FontWeight.bold);

  static TextStyle bodyLarge(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge ?? _fallback(fontSize: 16);

  static TextStyle bodyMedium(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? _fallback(fontSize: 14);

  static TextStyle bodySmall(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall ?? _fallback(fontSize: 12);

  static TextStyle labelLarge(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge ?? _fallback(fontSize: 14);

  static TextStyle labelMedium(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium ?? _fallback(fontSize: 12);

  static TextStyle labelSmall(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall ?? _fallback(fontSize: 11);

  /// A utility that applies the Inter font family to a [TextStyle] while
  /// keeping its other properties. Use when you need a one-off variant.
  static TextStyle withInter(TextStyle style) => style.copyWith(
        fontFamily: _fontFamily,
      );

  /// The preferred body style for emphasized, medium-weight text.
  static TextStyle bodyMediumSemibold(BuildContext context) =>
      bodyMedium(context).copyWith(fontWeight: FontWeight.w600);

  /// Small supporting text with a slightly heavier weight.
  static TextStyle bodySmallSemibold(BuildContext context) =>
      bodySmall(context).copyWith(fontWeight: FontWeight.w600);
}
