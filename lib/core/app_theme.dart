import 'package:flutter/material.dart';

export 'app_typography.dart';

/// Semantic colors that communicate meaning (success, warning, error, info).
///
/// These are independent of the brand color and must NOT be overridden.
/// They are intentionally hardcoded because they carry universal meaning
/// (red = error, green = success, amber = warning, blue = info) and should
/// remain consistent across light/dark mode and across all users.
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

  /// A subtle, accessible grey for disabled / placeholder states.
  static const Color disabled = Color(0xFF9E9E9E);
}

/// Centralized color and theme definitions — the SINGLE SOURCE OF TRUTH.
///
/// The application uses ONE universal brand color: **Pinoy POS Blue**.
/// There are no per-user accent colors. The same blue is used by Owner,
/// Admin, Staff, and the login screen in both light and dark mode.
///
/// The theme uses `ColorScheme.fromSeed()` with a vibrant blue seed and
/// custom surface tints to avoid the ash-gray appearance that default
/// Material 3 produces.
class AppColors {
  AppColors._();

  // ── Universal Pinoy POS Blue brand color ────────────────────────────

  /// The single brand seed color for the entire application.
  /// A modern, vibrant blue (blue.shade800) that produces a clean
  /// Material 3 ColorScheme in both light and dark mode.
  static const Color brandBlue = Color(0xFF1565C0); // blue.shade800

  // ── Light theme ─────────────────────────────────────────────────────

  static ThemeData getLightTheme() {
    return _buildTheme(
      seedColor: brandBlue,
      brightness: Brightness.light,
    );
  }

  // ── Dark theme ──────────────────────────────────────────────────────

  static ThemeData getDarkTheme() {
    return _buildTheme(
      seedColor: brandBlue,
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
      fontFamily: 'Inter',
      colorScheme: colorScheme,
      textTheme: Typography.material2021()
          .black
          .apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
            fontFamily: 'Inter',
          ),

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
        margin: EdgeInsets.zero,
      ),

      // ── App Bar theme ────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: isDark
            ? Colors.transparent
            : colorScheme.primary.withValues(alpha: 0.05),
        elevation: 0,
        scrolledUnderElevation: isDark ? 0 : 1,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),

      // ── Elevated button ──────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Filled button (primary CTA) ──────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          // Slightly taller padding for better touch targets.
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(48, 48),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontFamily: 'Inter',
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
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Inter',
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

      // ── SnackBar ──
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
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: colorScheme.onSurface,
        ),
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
    return hsl
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  // ── Premium button gradient ────────────────────────────────────────

  /// Returns a subtle vertical gradient for a primary button, derived
  /// from the brand color. Light mode uses a very subtle lift; dark
  /// mode uses a slightly deeper shade for depth.
  static LinearGradient? premiumButtonGradient(
    ColorScheme colorScheme,
    Brightness brightness,
  ) {
    final primary = colorScheme.primary;
    final darkened = _darken(primary, 0.06);
    final lightened = _darken(primary, -0.04);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: brightness == Brightness.light
          ? [lightened, primary]
          : [primary, darkened],
    );
  }
}
