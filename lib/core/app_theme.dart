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

  static const Color primaryBlue = Color(0xFF1C60DB);
  static const Color primaryBlueDark = Color(0xFF0C3392);
  static const Color primaryBlueLight = Color(0xFF2F80ED);

  // ── Dark mode foundation ─────────────────────────────────────────────

  static const Color darkBackground = Color(0xFF070B14);
  static const Color darkSurface = Color(0xFF0F1728);
  static const Color darkSurfaceElevated = Color(0xFF121D35);
  static const Color darkSurfaceStrong = Color(0xFF17264A);
  static const Color darkBorder = Color(0xFF243455);
  static const Color darkDivider = Color(0xFF1B2942);

  // ── Dark mode text ───────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFC2CAD8);
  static const Color textMuted = Color(0xFF8994A8);
  static const Color textDisabled = Color(0xFF5D687A);

  // ── Light mode foundation ────────────────────────────────────────────

  static const Color lightBackground = Color(0xFFF5F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSoft = Color(0xFFEEF4FF);
  static const Color lightBorder = Color(0xFFD9E1EF);
  static const Color lightDivider = Color(0xFFE7ECF4);

  // ── Light mode text ──────────────────────────────────────────────────

  static const Color lightTextPrimary = Color(0xFF172033);
  static const Color lightTextSecondary = Color(0xFF4F5B70);
  static const Color lightTextMuted = Color(0xFF7B879A);
  static const Color lightTextDisabled = Color(0xFFA8B1C0);

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

  static const double chip = sm;
  static const double control = md;
  static const double input = lg;
  static const double card = 18;
  static const double dialog = xl;
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

  static const Color primary = AppColorTokens.primaryBlue;
  static const Color primaryLight = AppColorTokens.primaryBlueLight;
  static const Color primaryDark = AppColorTokens.primaryBlueDark;
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

  static const Color info = Color(0xFF0891B2);
  static const Color onInfo = AppColorTokens.onPrimaryBlue;
  static const Color infoContainer = Color(0xFFCFFAFE);
  static const Color onInfoContainer = Color(0xFF0E5C6D);

  // ── Purple accent for AI / advanced features ─────────────────────────

  static const Color purple = Color(0xFF7C3AED);
  static const Color onPurple = AppColorTokens.onPrimaryBlue;
  static const Color purpleContainer = Color(0xFFEDE9FE);
  static const Color onPurpleContainer = Color(0xFF4C1D95);

  /// Neutral grey for non-emphasised actions and secondary icons.
  static const Color neutral = Color(0xFF64748B);
  static const Color onNeutral = AppColorTokens.onPrimaryBlue;
  static const Color neutralContainer = Color(0xFFF1F5F9);
  static const Color onNeutralContainer = Color(0xFF334155);

  static const Color disabled = Color(0xFFA8B1C0);

  // ── Theme-aware resolution: light constant → dark variant ─────────────

  static final Map<Color, Color> _darkForLight = {
    // Primary family
    primary: AppColorTokens.primaryBlue,
    primaryLight: const Color(0xFF60A5FA),
    primaryDark: AppColorTokens.primaryBlue,

    // Success family
    success: const Color(0xFF4ADE80),
    successContainer: const Color(0xFF12351F),
    onSuccessContainer: const Color(0xFF86EFAC),

    // Warning family
    warning: const Color(0xFFFBBF24),
    warningContainer: const Color(0xFF3A2A0A),
    onWarningContainer: const Color(0xFFFDE68A),

    // Error / danger family
    error: const Color(0xFFF87171),
    errorContainer: const Color(0xFF3A1518),
    onErrorContainer: const Color(0xFFFECACA),

    // Info family
    info: const Color(0xFF06B6D4),
    infoContainer: const Color(0xFF0A3038),
    onInfoContainer: const Color(0xFF9AF1F7),

    // Purple family
    purple: const Color(0xFF8B5CF6),
    purpleContainer: const Color(0xFF291A4A),
    onPurpleContainer: const Color(0xFFD8B4FE),

    // Neutral family
    neutral: const Color(0xFF94A3B8),
    neutralContainer: const Color(0xFF1E293B),
    onNeutralContainer: const Color(0xFFF1F5F9),

    // On-colors (onSuccess/onError/onNeutral/onPurple/onInfo alias onPrimary)
    onPrimary: AppColorTokens.onPrimaryBlue,

    // Disabled
    disabled: AppColorTokens.textDisabled,
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
  static const Color secondarySurface = AppColorTokens.primaryBlueLight;
  static const Color successSurface = Color(0xFF16A34A);
  static const Color warningSurface = Color(0xFFD97706);
  static const Color infoSurface = Color(0xFF0891B2);
  static const Color errorSurface = Color(0xFFDC2626);
  static const Color neutralSurface = Color(0xFF64748B);
  static const Color purpleSurface = Color(0xFF7C3AED);

  static final Map<Color, Color> _darkSurfaceForLight = {
    primarySurface: AppColorTokens.primaryBlue,
    secondarySurface: AppColorTokens.primaryBlueDark,
    successSurface: const Color(0xFF12351F),
    warningSurface: const Color(0xFF3A2A0A),
    errorSurface: const Color(0xFF3A1518),
    neutralSurface: const Color(0xFF1E293B),
    infoSurface: const Color(0xFF0A3038),
    purpleSurface: const Color(0xFF291A4A),
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

    final primary = AppColorTokens.primaryBlue;
    final onPrimary = AppColorTokens.onPrimaryBlue;
    final primaryContainer = isDark
        ? AppColorTokens.primaryBlueDark
        : AppColorTokens.lightSurfaceSoft;
    final onPrimaryContainer = isDark
        ? AppColorTokens.textPrimary
        : AppColorTokens.lightTextPrimary;

    final secondary = AppColorTokens.primaryBlueLight;
    final onSecondary = isDark ? AppColorTokens.textPrimary : AppColorTokens.onPrimaryBlue;
    final secondaryContainer = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurface;
    final onSecondaryContainer = isDark
        ? AppColorTokens.textPrimary
        : AppColorTokens.lightTextPrimary;

    final tertiary = AppColorTokens.primaryBlueDark;
    final onTertiary = AppColorTokens.onPrimaryBlue;
    final tertiaryContainer = isDark
        ? AppColorTokens.primaryBlueDark
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
    final inversePrimary = AppColorTokens.primaryBlueLight;
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
        ? AppColorTokens.primaryBlueDark
        : AppColorTokens.primaryBlue;
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
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
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
          backgroundBuilder: AppColors.elevatedButtonBackgroundBuilder,
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
          backgroundBuilder: AppColors.filledButtonBackgroundBuilder,
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

        border: _inputBorder(colorScheme.outlineVariant, 1.0),
        enabledBorder: _inputBorder(colorScheme.outlineVariant, 1.0),
        disabledBorder: _inputBorder(
          colorScheme.outlineVariant.withValues(alpha: 0.5),
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
          fontSize: 14,
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
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: colorScheme.onSurface,
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

  // ── Login / primary gradient ────────────────────────────────────────

  /// Returns the horizontal blue gradient used by the login screen and
  /// primary gradient buttons. It is the single source of truth for that
  /// gradient and adapts to both light and dark mode.
  static LinearGradient loginGradient(Brightness brightness) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        AppSemanticColors.resolve(AppSemanticColors.primaryLight, brightness),
        AppSemanticColors.resolve(AppSemanticColors.primaryDark, brightness),
      ],
    );
  }

  /// Background builder used by [FilledButtonThemeData] and
  /// [ElevatedButtonThemeData] to give primary buttons the same horizontal
  /// gradient as the login screen. Non-primary colors are rendered as flat
  /// fills, and disabled buttons receive the standard dimming overlay.
  static Widget _primaryButtonBackgroundBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child, {
    required bool treatNullStyleAsPrimary,
  }) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final style = context.widget is FilledButton
        ? (context.widget as FilledButton).style
        : context.widget is ElevatedButton
            ? (context.widget as ElevatedButton).style
            : null;
    final bg = style?.backgroundColor;

    final disabled = states.contains(WidgetState.disabled);
    const borderRadius = BorderRadius.all(Radius.circular(AppRadius.control));

    final bool isPrimary;
    if (bg != null) {
      final enabledStates = <WidgetState>{...states}
        ..remove(WidgetState.disabled);
      final enabledBg = bg.resolve(enabledStates);
      isPrimary = enabledBg == cs.primary;
    } else {
      isPrimary = treatNullStyleAsPrimary;
    }

    if (isPrimary) {
      return _GradientOverlayBackground(
        gradient: loginGradient(brightness),
        borderRadius: borderRadius,
        disabled: disabled,
        child: child,
      );
    }

    final resolvedBg = bg!.resolve(states);
    final enabledStates = <WidgetState>{...states}
      ..remove(WidgetState.disabled);
    final enabledBg = bg.resolve(enabledStates);
    final bgColor = resolvedBg ??
        enabledBg?.withValues(alpha: 0.12) ??
        cs.onSurface.withValues(alpha: 0.12);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  static Widget filledButtonBackgroundBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) {
    return _primaryButtonBackgroundBuilder(
      context,
      states,
      child,
      treatNullStyleAsPrimary: true,
    );
  }

  static Widget elevatedButtonBackgroundBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) {
    return _primaryButtonBackgroundBuilder(
      context,
      states,
      child,
      treatNullStyleAsPrimary: false,
    );
  }
}

/// Layer used by [AppColors.filledButtonBackgroundBuilder] and
/// [AppColors.elevatedButtonBackgroundBuilder] to paint a rounded gradient
/// and an optional disabled overlay behind a button's child.
class _GradientOverlayBackground extends StatelessWidget {
  final LinearGradient gradient;
  final BorderRadius borderRadius;
  final bool disabled;
  final Widget? child;

  const _GradientOverlayBackground({
    required this.gradient,
    required this.borderRadius,
    required this.disabled,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: borderRadius,
            ),
          ),
        ),
        if (disabled)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.12),
                borderRadius: borderRadius,
              ),
            ),
          ),
        child ?? const SizedBox.shrink(),
      ],
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
