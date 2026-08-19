import 'package:flutter/material.dart';

/// Centralized typography helpers for consistent bold/semibold text styles
/// across the app. Use these instead of `copyWith(fontWeight: FontWeight.bold)`.
class AppTypography {
  AppTypography._();

  static TextStyle headlineSmallBold(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ) ??
      const TextStyle(fontSize: 24, fontWeight: FontWeight.bold);

  static TextStyle titleLargeBold(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ) ??
      const TextStyle(fontSize: 22, fontWeight: FontWeight.bold);

  static TextStyle titleMediumBold(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ) ??
      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

  static TextStyle titleMediumSemibold(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ) ??
      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  static TextStyle titleSmallBold(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ) ??
      const TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

  static TextStyle headlineSmallSemibold(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ) ??
      const TextStyle(fontSize: 24, fontWeight: FontWeight.w600);
}

class AppColors {
  static const Map<String, Color> accentColors = {
    'green': Colors.green,
    'blue': Colors.blue,
    'purple': Colors.purple,
    'indigo': Colors.indigo,
    'orange': Colors.orange,
    'amber': Colors.amber,
    'cyan': Colors.cyan,
    'teal': Colors.teal,
    'red': Colors.red,
    'pink': Colors.pink,
  };

  static Color getAccentColor(String colorName) {
    return accentColors[colorName] ?? Colors.green;
  }

  static ThemeData getLightTheme(String accentColorName) {
    final accentColor = getAccentColor(accentColorName);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: Brightness.light,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }

  static ThemeData getDarkTheme(String accentColorName) {
    final accentColor = getAccentColor(accentColorName);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: Brightness.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }
}
