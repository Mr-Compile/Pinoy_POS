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

/// Centralized color and theme definitions.
///
/// The application has TWO visual theme contexts:
///
/// 1. **Login / Unauthenticated** — always uses a fixed **Blue** accent,
///    independent of any user preference.
/// 2. **Authenticated Application** — uses the current user's saved
///    `color_preference` from the `users` table.  Only 5 accent colors
///    are user-selectable: green, purple, teal, orange, indigo.
class AppColors {
  AppColors._();

  // ── User-selectable accent colors (authenticated app) ──────────────

  /// The 5 approved user-selectable accent colors.
  /// Blue is intentionally excluded — it is reserved for the Login screen.
  static const Map<String, Color> userAccentColors = {
    'green': Colors.green,
    'purple': Colors.purple,
    'teal': Colors.teal,
    'orange': Colors.orange,
    'indigo': Colors.indigo,
  };

  /// The default authenticated accent color when a user's preference is
  /// null, empty, or contains a removed/invalid value.
  static const String defaultUserAccent = 'green';

  /// Login screen fixed accent color.
  static const String loginAccent = 'blue';
  static const Color _loginColor = Colors.blue;

  // ── Migration helper ───────────────────────────────────────────────

  /// Returns a valid user accent color name.
  ///
  /// If [preference] is null, empty, or contains a removed/invalid color
  /// (e.g. 'blue', 'amber', 'cyan', 'red', 'pink'), it falls back to
  /// [defaultUserAccent] ('green').
  static String validateUserAccent(String? preference) {
    if (preference == null || preference.isEmpty) return defaultUserAccent;
    if (userAccentColors.containsKey(preference)) return preference;
    return defaultUserAccent;
  }

  /// Returns the [Color] for a validated user accent name.
  /// Always call [validateUserAccent] first if the preference may be
  /// invalid.
  static Color getUserAccentColor(String colorName) {
    return userAccentColors[colorName] ?? Colors.green;
  }

  // ── Login theme (fixed Blue) ───────────────────────────────────────

  static ThemeData getLoginLightTheme() {
    return _buildTheme(
      seedColor: _loginColor,
      brightness: Brightness.light,
    );
  }

  static ThemeData getLoginDarkTheme() {
    return _buildTheme(
      seedColor: _loginColor,
      brightness: Brightness.dark,
    );
  }

  // ── Authenticated user theme ───────────────────────────────────────

  static ThemeData getLightTheme(String accentColorName) {
    final accentColor = userAccentColors[accentColorName] ?? Colors.green;
    return _buildTheme(
      seedColor: accentColor,
      brightness: Brightness.light,
    );
  }

  static ThemeData getDarkTheme(String accentColorName) {
    final accentColor = userAccentColors[accentColorName] ?? Colors.green;
    return _buildTheme(
      seedColor: accentColor,
      brightness: Brightness.dark,
    );
  }

  // ── Shared theme builder ───────────────────────────────────────────

  static ThemeData _buildTheme({
    required Color seedColor,
    required Brightness brightness,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
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
