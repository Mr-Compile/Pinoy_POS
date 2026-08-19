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

/// Semantic colors that are independent of the user's accent preference.
///
/// These colors communicate meaning (success, warning, error, info) and
/// must NOT be overridden by the user's selected accent color.
class AppSemanticColors {
  AppSemanticColors._();

  static const Color success = Color(0xFF2E7D32);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFC8E6C9);
  static const Color onSuccessContainer = Color(0xFF00390A);

  static const Color warning = Color(0xFFE65100);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFFE0B2);
  static const Color onWarningContainer = Color(0xFF5A1A00);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);

  static const Color info = Color(0xFF0288D1);
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFFB3E5FC);
  static const Color onInfoContainer = Color(0xFF001F3F);
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
///
/// The theme uses `ColorScheme.fromSeed()` with **vibrant seed colors**
/// (not the muted Material default 500-shade) and custom surface tints
/// to avoid the ash-gray appearance that default Material 3 produces.
class AppColors {
  AppColors._();

  // ── User-selectable accent colors (authenticated app) ──────────────

  /// The 5 approved user-selectable accent colors mapped to vibrant
  /// seed values.  We use deeper shades (600-700) as seeds because
  /// `ColorScheme.fromSeed` lightens the primary, and using the 500
  /// shade produces overly muted results.
  static const Map<String, Color> userAccentColors = {
    'green': Color(0xFF2E7D32), // green.shade700 — vibrant
    'purple': Color(0xFF7B1FA2), // purple.shade700 — vibrant
    'teal': Color(0xFF00695C), // teal.shade800 — vibrant
    'orange': Color(0xFFE65100), // orange.shade800 — vibrant
    'indigo': Color(0xFF283593), // indigo.shade800 — vibrant
  };

  /// The default authenticated accent color when a user's preference is
  /// null, empty, or contains a removed/invalid value.
  static const String defaultUserAccent = 'green';

  /// Login screen fixed accent color.
  static const String loginAccent = 'blue';
  static const Color _loginColor = Color(0xFF1565C0); // blue.shade800

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
    return userAccentColors[colorName] ?? userAccentColors['green']!;
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
    final accentColor = userAccentColors[accentColorName] ?? userAccentColors['green']!;
    return _buildTheme(
      seedColor: accentColor,
      brightness: Brightness.light,
    );
  }

  static ThemeData getDarkTheme(String accentColorName) {
    final accentColor = userAccentColors[accentColorName] ?? userAccentColors['green']!;
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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // ── Scaffold background ──────────────────────────────────────
      // Use a slightly tinted scaffold background instead of pure
      // neutral gray.  In light mode this is a very subtle warm-neutral;
      // in dark mode it's a deep neutral with a hint of the accent.
      scaffoldBackgroundColor: isDark
          ? _darkScaffoldBackground(colorScheme)
          : _lightScaffoldBackground(colorScheme),

      // ── Card theme ───────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        // In dark mode, cards use a slightly lighter surface than the
        // scaffold to create tonal depth without relying on shadows.
        color: isDark ? colorScheme.surfaceContainerLow : null,
        surfaceTintColor: isDark ? Colors.transparent : null,
      ),

      // ── App Bar theme ────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark
            ? colorScheme.surface
            : colorScheme.surface,
        surfaceTintColor: isDark ? Colors.transparent : colorScheme.primary.withValues(alpha: 0.05),
        elevation: 0,
        scrolledUnderElevation: isDark ? 0 : 1,
      ),

      // ── Elevated button ──────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // ── Filled button (primary CTA) ──────────────────────────────
      // In dark mode, primary filled buttons get a subtle gradient
      // derived from the accent color for a premium feel.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          // Slightly taller padding for better touch targets.
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // ── Input decoration ─────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerLow,
      ),

      // ── Navigation bar (mobile bottom nav) ───────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surface,
        surfaceTintColor: isDark ? Colors.transparent : null,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // ── Navigation rail (tablet/desktop) ─────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surface,
        selectedIconTheme: IconThemeData(
          color: colorScheme.primary,
        ),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // ── FAB theme ────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: isDark ? 2 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── Dialog theme ─────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surface,
        surfaceTintColor: isDark ? Colors.transparent : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Divider ──────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ── SnackBar (used by dead code but kept for safety) ─────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // ── Chip theme ───────────────────────────────────────────────
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),

      // ── List tile ────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ── Custom surface helpers ─────────────────────────────────────────

  /// Light mode scaffold: a very subtle warm-neutral, not pure gray.
  static Color _lightScaffoldBackground(ColorScheme cs) {
    // Use surfaceContainerLowest with a very slight tint to avoid
    // the flat gray look.  Falls back to a near-white neutral.
    return cs.surfaceContainerLowest.withValues(alpha: 0.96);
  }

  /// Dark mode scaffold: a deep neutral with subtle accent influence.
  /// This creates depth — the scaffold is darker than cards/surfaces.
  static Color _darkScaffoldBackground(ColorScheme cs) {
    // Blend the surface with a darkened version to push it deeper
    // than the card surface, creating visual layering.
    return _darken(cs.surface, 0.04);
  }

  /// Darken a color by [amount] (0.0–1.0).
  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  // ── Dark mode premium button gradient ──────────────────────────────

  /// Returns a subtle vertical gradient for a primary button in dark
  /// mode, derived from the active accent color.
  ///
  /// The gradient goes from the primary color (top) to a slightly
  /// darkened primary (bottom), creating a subtle depth effect.
  /// In light mode this returns null (solid color is preferred).
  static LinearGradient? premiumButtonGradient(ColorScheme colorScheme, Brightness brightness) {
    if (brightness == Brightness.light) return null;
    final primary = colorScheme.primary;
    final darkened = _darken(primary, 0.06);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [primary, darkened],
    );
  }
}
