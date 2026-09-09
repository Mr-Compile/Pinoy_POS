import 'package:flutter/material.dart';

export 'app_typography.dart';

/// Pinoy POS canonical color tokens.
///
/// These are the single source of truth for every color value in the app.
/// UI code should not use raw `Color(...)` or `Colors.*`; it should consume
/// these tokens or the [ColorScheme] derived from them.
class AppColorTokens {
  AppColorTokens._();

  // ── Primary blue family ────────────────────────────────────────────────

  /// Light-mode primary brand blue.
  static const Color lightPrimary = Color(0xFF2563C7);

  /// Dark-mode primary brand blue.
  static const Color primaryBlue = Color(0xFF2C68D7);

  /// Strong, saturated brand blue (CTA emphasis / app bars / filled buttons).
  static const Color primaryBlueStrong = Color(0xFF1B4CAF);

  /// Deep brand blue (gradient end, tertiary accents).
  static const Color primaryBlueDeep = Color(0xFF0C3594);

  /// Lighter brand blue (gradient start, secondary accents).
  static const Color primaryBlueLight = Color(0xFF4B82E9);

  // ── Dark mode foundation ─────────────────────────────────────────────

  static const Color darkBackground = Color(0xFF070D19);
  static const Color darkSurface = Color(0xFF121C31);
  static const Color darkSurfaceElevated = Color(0xFF152348);
  static const Color darkSurfaceStrong = Color(0xFF1A2445);
  static const Color darkBorder = Color(0xFF263A63);
  static const Color darkDivider = Color(0xFF1A2445);

  // ── Dark mode text ───────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFF1F4F7);
  static const Color textSecondary = Color(0xFFB8C5E0);
  static const Color textMuted = Color(0xFF8C9AB8);

  // ── Light mode foundation ────────────────────────────────────────────

  static const Color lightBackground = Color(0xFFF5F8FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSoft = Color(0xFFEEF4FF);
  static const Color lightBorder = Color(0xFFD7E0EE);
  static const Color lightDivider = Color(0xFFE7ECF4);

  // ── Light mode text ──────────────────────────────────────────────────

  static const Color lightTextPrimary = Color(0xFF172033);
  static const Color lightTextSecondary = Color(0xFF52627A);
  static const Color lightTextMuted = Color(0xFF8A9AB3);

  // ── On-color helper ──────────────────────────────────────────────────

  static const Color onPrimaryBlue = Color(0xFFFFFFFF);
}

/// Centralized radius tokens so cards, buttons, inputs and dialogs share a
/// consistent rounding scale instead of scattering magic `BorderRadius` values.
class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Rounded square icon badges and prefix/suffix icon containers.
  static const double icon = 11;

  /// Full pill-shaped chips and status badges.
  static const double pill = 20;

  static const double chip = sm;
  static const double control = md;
  static const double input = md;
  static const double card = 18;
  static const double dialog = 22;
  static const double fab = lg;
  static const double menu = lg;
}

/// Semantic colors that communicate meaning (primary, success, warning, error,
/// info, purple, neutral, disabled).
///
/// The values in this class are the canonical light-mode roles. Each role has
/// an explicit dark-mode counterpart returned by [resolve] so the UI stays
/// readable in both themes without sprinkling theme checks through screens.
class AppSemanticColors {
  AppSemanticColors._();

  // ── Primary color role ───────────────────────────────────────────────

  static const Color primary = AppColorTokens.lightPrimary;
  static const Color primaryLight = AppColorTokens.primaryBlue;
  static const Color primaryDark = AppColorTokens.primaryBlueStrong;
  static const Color onPrimary = AppColorTokens.onPrimaryBlue;

  // ── Status and feedback colors (restrained, not oversaturated) ───────

  static const Color success = Color(0xFF16A34A);
  static const Color onSuccess = AppColorTokens.onPrimaryBlue;
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color onSuccessContainer = Color(0xFF14532D);

  static const Color warning = Color(0xFFD97706);
  static const Color onWarning = AppColorTokens.onPrimaryBlue;
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarningContainer = Color(0xFF78350F);

  static const Color error = Color(0xFFDC2626);
  static const Color onError = AppColorTokens.onPrimaryBlue;
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF7F1D1D);

  /// Info uses the primary blue family.
  static const Color info = AppColorTokens.primaryBlueLight;
  static const Color onInfo = AppColorTokens.onPrimaryBlue;
  static const Color infoContainer = AppColorTokens.lightSurfaceSoft;

  // ── Legacy "purple" accent for AI / advanced features.
  ///
  /// This is now mapped into the deep end of the primary blue family so the
  /// app keeps one cohesive palette while preserving existing call sites.
  static const Color purple = AppColorTokens.primaryBlueStrong;
  static const Color onPurple = AppColorTokens.onPrimaryBlue;
  static const Color purpleContainer = AppColorTokens.lightSurfaceSoft;
  static const Color onPurpleContainer = AppColorTokens.lightTextPrimary;

  /// Neutral grey for non-emphasised actions and secondary icons.
  static const Color neutral = AppColorTokens.lightTextSecondary;
  static const Color onNeutral = AppColorTokens.onPrimaryBlue;
  static const Color neutralContainer = AppColorTokens.lightSurfaceSoft;

  // ── Dashboard accent colors (from the dashboard mockup palette) ─────
  //
  // Used for icon badges, pills, chart accents and role chips where the
  // primary blue family needs a distinct sibling hue (e.g. GCash rows,
  // Admin role chips, staff avatars).

  /// Accent colors for dashboards, charts and role badges.
  static const Color teal = Color(0xFF06B6D4);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink = Color(0xFFEC4899);

  // ── Theme-aware resolution: light constant → dark variant ─────────────

  static final Map<Color, Color> _darkForLight = {
    // Primary family
    primary: AppColorTokens.primaryBlue,
    primaryLight: AppColorTokens.primaryBlueLight,
    primaryDark: AppColorTokens.primaryBlueDeep,

    // Success family
    success: const Color(0xFF22C55E),
    successContainer: const Color(0xFF12351F),
    onSuccessContainer: const Color(0xFF86EFAC),

    // Warning family
    warning: const Color(0xFFF59E0B),
    warningContainer: const Color(0xFF3A2A0A),
    onWarningContainer: const Color(0xFFFDE68A),

    // Error / danger family
    error: const Color(0xFFEF4444),
    errorContainer: const Color(0xFF3A1518),
    onErrorContainer: const Color(0xFFFECACA),

    // Info family (primary blue family)
    info: AppColorTokens.primaryBlue,
    infoContainer: AppColorTokens.darkSurfaceStrong,

    // Purple (now deep blue) family
    // `purple` equals `primaryDark`, so it resolves through that entry.

    // Neutral family
    neutral: AppColorTokens.textSecondary,

    // Dashboard accents
    teal: const Color(0xFF22D3EE),
    violet: const Color(0xFFA78BFA),
    pink: const Color(0xFFF472B6),

    // On-colors (onSuccess/onError/onNeutral/onPurple/onInfo alias onPrimary)
    onPrimary: AppColorTokens.onPrimaryBlue,
  };

  /// Returns the theme-aware variant of a [light] semantic color.
  static Color resolve(Color light, Brightness brightness) {
    if (brightness == Brightness.light) return light;
    return _darkForLight[light] ?? light;
  }

  /// Convenience for resolving an on-color.
  static Color resolveOn(Color lightOn, Brightness brightness) {
    return resolve(lightOn, brightness);
  }

  // ── Semantic surfaces for filled buttons / quick actions ───────────────

  static const Color primarySurface = AppColorTokens.primaryBlue;
  static const Color secondarySurface = AppColorTokens.lightPrimary;
  static const Color successSurface = Color(0xFF16A34A);
  static const Color warningSurface = Color(0xFFD97706);
  static const Color infoSurface = AppColorTokens.primaryBlueLight;
  static const Color errorSurface = Color(0xFFDC2626);
  static const Color neutralSurface = AppColorTokens.lightBorder;
  static const Color purpleSurface = AppColorTokens.primaryBlueStrong;

  static final Map<Color, Color> _darkSurfaceForLight = {
    primarySurface: AppColorTokens.primaryBlue,
    secondarySurface: AppColorTokens.primaryBlueStrong,
    successSurface: const Color(0xFF12351F),
    warningSurface: const Color(0xFF3A2A0A),
    errorSurface: const Color(0xFF3A1518),
    neutralSurface: AppColorTokens.darkSurfaceElevated,
    infoSurface: AppColorTokens.darkSurfaceStrong,
    purpleSurface: AppColorTokens.primaryBlueDeep,
  };

  /// Returns the dark-mode surface color for a light-mode semantic [surface].
  static Color resolveSurface(Color surface, Brightness brightness) {
    if (brightness == Brightness.light) return surface;
    return _darkSurfaceForLight[surface] ?? surface;
  }

  /// Returns a foreground color that is legible on [background].
  ///
  /// In light mode, light backgrounds get [AppColorTokens.lightTextPrimary]
  /// and dark backgrounds get white. In dark mode, light backgrounds get
  /// [AppColorTokens.lightTextPrimary] and dark backgrounds get
  /// [AppColorTokens.textPrimary].
  static Color contrastFor(
    Color background,
    Brightness brightness, {
    double threshold = 0.38,
  }) {
    final isLightBackground = background.computeLuminance() > threshold;
    if (isLightBackground) {
      return AppColorTokens.lightTextPrimary;
    }
    return brightness == Brightness.light
        ? AppColorTokens.onPrimaryBlue
        : AppColorTokens.textPrimary;
  }
}

/// Centralized color and theme definitions.
///
/// The application builds a Material 3 [ColorScheme] directly from the
/// canonical Pinoy POS palette so every screen, component and dialog shares
/// one visual language in both light and dark mode.
class AppColors {
  AppColors._();

  // ── ColorSchemes ────────────────────────────────────────────────────

  static ColorScheme getLightColorScheme() => _buildColorScheme(Brightness.light);
  static ColorScheme getDarkColorScheme() => _buildColorScheme(Brightness.dark);

  // ── Themes ──────────────────────────────────────────────────────────

  static ThemeData getLightTheme() => _buildTheme(Brightness.light);
  static ThemeData getDarkTheme() => _buildTheme(Brightness.dark);

  // ── Shared color scheme builder ─────────────────────────────────────

  static ColorScheme _buildColorScheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final primary = isDark
        ? AppColorTokens.primaryBlueLight
        : AppColorTokens.lightPrimary;
    final onPrimary = AppColorTokens.onPrimaryBlue;
    final primaryContainer = isDark
        ? AppColorTokens.primaryBlue
        : AppColorTokens.lightSurfaceSoft;
    final onPrimaryContainer = isDark
        ? AppColorTokens.textPrimary
        : AppColorTokens.lightTextPrimary;

    final secondary = isDark
        ? AppColorTokens.primaryBlue
        : AppColorTokens.primaryBlue;
    final onSecondary = AppColorTokens.onPrimaryBlue;
    final secondaryContainer = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurface;
    final onSecondaryContainer = isDark
        ? AppColorTokens.textPrimary
        : AppColorTokens.lightTextPrimary;

    final tertiary = isDark
        ? AppColorTokens.primaryBlueDeep
        : AppColorTokens.primaryBlueStrong;
    final onTertiary = AppColorTokens.onPrimaryBlue;
    final tertiaryContainer = isDark
        ? AppColorTokens.primaryBlueStrong
        : AppColorTokens.lightSurfaceSoft;
    final onTertiaryContainer = isDark
        ? AppColorTokens.textPrimary
        : AppColorTokens.lightTextPrimary;

    final error = AppSemanticColors.resolve(AppSemanticColors.error, brightness);
    final onError = AppSemanticColors.resolveOn(AppSemanticColors.onError, brightness);
    final errorContainer = AppSemanticColors.resolve(
      AppSemanticColors.errorContainer,
      brightness,
    );
    final onErrorContainer = AppSemanticColors.resolveOn(
      AppSemanticColors.onErrorContainer,
      brightness,
    );

    final surface = isDark ? AppColorTokens.darkSurface : AppColorTokens.lightSurface;
    final onSurface = isDark ? AppColorTokens.textPrimary : AppColorTokens.lightTextPrimary;
    final onSurfaceVariant = isDark ? AppColorTokens.textMuted : AppColorTokens.lightTextMuted;

    final surfaceDim = isDark ? AppColorTokens.darkBackground : AppColorTokens.lightBackground;
    final surfaceBright = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurface;
    final surfaceContainerLowest = surfaceDim;
    final surfaceContainerLow = surface;
    final surfaceContainer = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurface;
    final surfaceContainerHigh = isDark
        ? AppColorTokens.darkSurfaceStrong
        : AppColorTokens.lightSurfaceSoft;
    final surfaceContainerHighest = surfaceContainerHigh;

    final outline = isDark ? AppColorTokens.darkBorder : AppColorTokens.lightBorder;
    final outlineVariant = isDark ? AppColorTokens.darkDivider : AppColorTokens.lightDivider;

    final inverseSurface = isDark
        ? AppColorTokens.lightSurface
        : AppColorTokens.darkSurface;
    final onInverseSurface = isDark
        ? AppColorTokens.lightTextPrimary
        : AppColorTokens.textPrimary;
    final inversePrimary = AppColorTokens.primaryBlue;
    final surfaceTint = AppColorTokens.primaryBlue;

    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      primaryFixed: primaryContainer,
      primaryFixedDim: primary,
      onPrimaryFixed: onPrimaryContainer,
      onPrimaryFixedVariant: isDark ? AppColorTokens.textMuted : AppColorTokens.lightTextSecondary,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      secondaryFixed: secondaryContainer,
      secondaryFixedDim: secondary,
      onSecondaryFixed: onSecondaryContainer,
      onSecondaryFixedVariant: isDark ? AppColorTokens.textMuted : AppColorTokens.lightTextSecondary,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      tertiaryFixed: tertiaryContainer,
      tertiaryFixedDim: tertiary,
      onTertiaryFixed: onTertiaryContainer,
      onTertiaryFixedVariant: isDark ? AppColorTokens.textMuted : AppColorTokens.lightTextSecondary,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      surfaceDim: surfaceDim,
      surfaceBright: surfaceBright,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: AppColorTokens.darkBackground.withValues(alpha: 0.5),
      scrim: AppColorTokens.darkBackground.withValues(alpha: 0.6),
      inverseSurface: inverseSurface,
      onInverseSurface: onInverseSurface,
      inversePrimary: inversePrimary,
      surfaceTint: surfaceTint,
    );
  }

  // ── Shared theme builder ────────────────────────────────────────────

  static ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = _buildColorScheme(brightness);
    final isDark = brightness == Brightness.dark;

    final appBarBackground = isDark
        ? AppColorTokens.primaryBlueStrong
        : AppColorTokens.lightPrimary;
    final appBarForeground = AppColorTokens.onPrimaryBlue;

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
      scaffoldBackgroundColor: isDark
          ? AppColorTokens.darkBackground
          : AppColorTokens.lightBackground,

      // ── Card theme ───────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colorScheme.outline),
        ),
        color: colorScheme.surface,
        surfaceTintColor: isDark ? Colors.transparent : null,
        margin: EdgeInsets.zero,
      ),

      // ── App Bar theme ────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: appBarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: isDark ? 0 : 1,
        foregroundColor: appBarForeground,
        iconTheme: IconThemeData(color: appBarForeground),
        actionsIconTheme: IconThemeData(color: appBarForeground),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: appBarForeground,
        ),
      ),

      // ── Elevated button ──────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Filled button (primary CTA) ──────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Input decoration ─────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        constraints: const BoxConstraints(minHeight: 56),

        border: _inputBorder(colorScheme.outline, 1.0),
        enabledBorder: _inputBorder(colorScheme.outline, 1.0),
        disabledBorder: _inputBorder(
          colorScheme.outline.withValues(alpha: 0.5),
          1.0,
        ),
        focusedBorder: _inputBorder(colorScheme.primary, 1.5),
        errorBorder: _inputBorder(colorScheme.error, 1.0),
        focusedErrorBorder: _inputBorder(colorScheme.error, 1.5),

        labelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? colorScheme.error
              : states.contains(WidgetState.disabled)
                  ? colorScheme.onSurface.withValues(alpha: 0.38)
                  : colorScheme.onSurfaceVariant;
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: color,
          );
        }),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? colorScheme.error
              : states.contains(WidgetState.focused)
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant;
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          );
        }),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
        ),
        helperStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        errorStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: colorScheme.error,
        ),
        errorMaxLines: 2,

        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return colorScheme.error;
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.focused)) return colorScheme.primary;
          return colorScheme.onSurfaceVariant;
        }),
        suffixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return colorScheme.error;
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.focused)) return colorScheme.primary;
          return colorScheme.onSurfaceVariant;
        }),
      ),

      // ── Text selection ───────────────────────────────────────────
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: colorScheme.primary,
      ),

      // ── Navigation bar (mobile bottom nav) ───────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: isDark ? Colors.transparent : null,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: colorScheme.onPrimaryContainer,
            );
          }
          return IconThemeData(
            color: colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
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
        backgroundColor: colorScheme.surfaceContainer,
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
          borderRadius: BorderRadius.circular(AppRadius.fab),
        ),
      ),

      // ── Dialog theme ─────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        alignment: Alignment.center,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: isDark ? Colors.transparent : null,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(
            color: isDark ? AppColorTokens.darkBorder : AppColorTokens.lightBorder,
          ),
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
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),

      // ── Chip theme ───────────────────────────────────────────────
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        backgroundColor: colorScheme.surface,
        selectedColor: colorScheme.primary,
        checkmarkColor: colorScheme.onPrimary,
        side: BorderSide(color: colorScheme.outline),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Inter',
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── List tile ────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }

  // ── Custom surface helpers ─────────────────────────────────────────

  static OutlineInputBorder _inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }

}

/// Convenience helpers for converting Flutter [Color]s into the formats that
/// PDF and Excel packages expect.
extension SemanticColorValue on Color {
  /// 32-bit ARGB value for `PdfColor.fromInt`.
  int get pdfValue => toARGB32();

  /// ARGB hex string for `ExcelColor.fromHexString`.
  String get excelHex =>
      toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
}
