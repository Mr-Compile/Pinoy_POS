import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// Common button color roles. Use `primary` for primary CTAs and use
/// semantic colors only when the action meaning matches (e.g. green for
/// save / new sale, red for delete, amber for warnings).
enum AppButtonColor { primary, success, warning, info, error, neutral }

/// Common button variants used across the app.
enum AppButtonVariant { filled, outlined, text, elevated, destructive }

/// Common button sizes. All sizes still respect the 48 dp touch target.
enum AppButtonSize { small, medium, large }

/// A unified, accessible button component.
///
/// Supports primary, secondary, outlined, text, elevated, and destructive
/// variants, plus an optional loading state that disables the button and swaps
/// the label for a spinner. All sizes keep a minimum 48 x 48 touch target.
///
/// Use the named color constructors ([AppButton.success], [AppButton.warning],
/// [AppButton.info], [AppButton.neutral]) or the [color] parameter to make
/// button meaning immediately visible. Avoid using every button in color —
/// reserve color for actions that benefit from it (save, delete, warnings,
/// help). For generic navigation, prefer [AppButtonColor.neutral].
class AppButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;
  final AppButtonColor color;

  const AppButton({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    required this.variant,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  });

  const AppButton.filled({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  }) : variant = AppButtonVariant.filled;

  const AppButton.outlined({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  }) : variant = AppButtonVariant.outlined;

  const AppButton.text({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  }) : variant = AppButtonVariant.text;

  const AppButton.elevated({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  }) : variant = AppButtonVariant.elevated;

  const AppButton.destructive({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  })  : color = AppButtonColor.error,
        variant = AppButtonVariant.destructive;

  const AppButton.success({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  })  : color = AppButtonColor.success,
        variant = AppButtonVariant.filled;

  const AppButton.warning({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  })  : color = AppButtonColor.warning,
        variant = AppButtonVariant.filled;

  const AppButton.info({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  })  : color = AppButtonColor.info,
        variant = AppButtonVariant.filled;

  const AppButton.neutral({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  })  : color = AppButtonColor.neutral,
        variant = AppButtonVariant.filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effectiveLabel = child ?? Text(label ?? '');

    final resolved = switch (size) {
      AppButtonSize.small => (
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          theme.textTheme.labelLarge,
          18.0
        ),
      AppButtonSize.medium => (
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          theme.textTheme.labelLarge,
          20.0
        ),
      AppButtonSize.large => (
          const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          theme.textTheme.titleSmall,
          22.0
        ),
    };

    final padding = resolved.$1;
    final textStyle = resolved.$2;
    final iconSize = resolved.$3;

    final (mainColor, onMainColor) = _resolveColors(cs, color);
    final labelColor = switch (variant) {
      AppButtonVariant.filled ||
      AppButtonVariant.elevated ||
      AppButtonVariant.destructive =>
        onMainColor,
      _ => mainColor,
    };

    final buttonChild = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: labelColor,
            ),
          )
        : _buildIconLabel(effectiveLabel, icon, iconSize, labelColor);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    final button = switch (variant) {
      AppButtonVariant.filled => _buildFilledButton(
          context,
          cs,
          shape,
          padding,
          textStyle,
          buttonChild,
          mainColor,
          onMainColor,
        ),
      AppButtonVariant.elevated => _buildElevatedButton(
          context,
          cs,
          shape,
          padding,
          textStyle,
          buttonChild,
          mainColor,
          onMainColor,
        ),
      AppButtonVariant.outlined => _buildOutlinedButton(
          context,
          shape,
          padding,
          textStyle,
          buttonChild,
          mainColor,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: mainColor,
            shape: shape,
            padding: padding,
            minimumSize: const Size(48, 48),
            textStyle: textStyle,
          ),
          child: buttonChild,
        ),
      AppButtonVariant.destructive => FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppSemanticColors.error,
            foregroundColor: AppSemanticColors.onError,
            shape: shape,
            padding: padding,
            minimumSize: const Size(48, 48),
            textStyle: textStyle,
          ),
          child: buttonChild,
        ),
    };

    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }

  /// Resolves the main and foreground colors for the chosen semantic role.
  (Color, Color) _resolveColors(ColorScheme cs, AppButtonColor color) {
    return switch (color) {
      AppButtonColor.primary => (cs.primary, cs.onPrimary),
      AppButtonColor.success =>
        (AppSemanticColors.success, AppSemanticColors.onSuccess),
      AppButtonColor.warning =>
        (AppSemanticColors.warning, AppSemanticColors.onWarning),
      AppButtonColor.info => (AppSemanticColors.info, AppSemanticColors.onInfo),
      AppButtonColor.error =>
        (AppSemanticColors.error, AppSemanticColors.onError),
      AppButtonColor.neutral =>
        (AppSemanticColors.neutral, AppSemanticColors.onNeutral),
    };
  }

  Widget _buildFilledButton(
    BuildContext context,
    ColorScheme cs,
    RoundedRectangleBorder shape,
    EdgeInsets padding,
    TextStyle? textStyle,
    Widget child,
    Color mainColor,
    Color onMainColor,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Primary color in dark mode gets a subtle premium gradient for visual
    // depth. Semantic and neutral colors use a flat fill so the color meaning
    // stays clean.
    if (color == AppButtonColor.primary &&
        !isLoading &&
        onPressed != null &&
        isDark) {
      final gradient = AppColors.premiumButtonGradient(cs, theme.brightness);
      if (gradient != null) {
        return _GradientFilledButton(
          onTap: onPressed,
          gradient: gradient,
          padding: padding,
          shape: shape,
          textStyle: textStyle,
          child: child,
        );
      }
    }

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: mainColor,
        foregroundColor: onMainColor,
        shape: shape,
        padding: padding,
        minimumSize: const Size(48, 48),
        textStyle: textStyle,
      ),
      child: child,
    );
  }

  Widget _buildElevatedButton(
    BuildContext context,
    ColorScheme cs,
    RoundedRectangleBorder shape,
    EdgeInsets padding,
    TextStyle? textStyle,
    Widget child,
    Color mainColor,
    Color onMainColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use a very light tint of the semantic color on the surface so the
    // button is visible but softer than a filled button.
    final background = isDark
        ? mainColor.withValues(alpha: 0.15)
        : mainColor.withValues(alpha: 0.08);

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: mainColor,
        shadowColor: mainColor.withValues(alpha: 0.15),
        elevation: isDark ? 2 : 1,
        shape: shape,
        padding: padding,
        minimumSize: const Size(48, 48),
        textStyle: textStyle,
      ),
      child: child,
    );
  }

  Widget _buildOutlinedButton(
    BuildContext context,
    RoundedRectangleBorder shape,
    EdgeInsets padding,
    TextStyle? textStyle,
    Widget child,
    Color mainColor,
  ) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: mainColor,
        side: BorderSide(color: mainColor.withValues(alpha: 0.7)),
        shape: shape,
        padding: padding,
        minimumSize: const Size(48, 48),
        textStyle: textStyle,
      ),
      child: child,
    );
  }

  Widget _buildIconLabel(Widget label, IconData? icon, double iconSize, Color color) {
    if (icon == null) {
      return DefaultTextStyle.merge(
        style: TextStyle(color: color),
        child: label,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: Spacing.sm),
        DefaultTextStyle.merge(
          style: TextStyle(color: color),
          child: label,
        ),
      ],
    );
  }
}

/// A dark-mode primary button with a subtle gradient, wrapped in a tappable
/// container. Kept private to [AppButton].
class _GradientFilledButton extends StatelessWidget {
  final VoidCallback? onTap;
  final LinearGradient gradient;
  final EdgeInsets padding;
  final RoundedRectangleBorder shape;
  final TextStyle? textStyle;
  final Widget child;

  const _GradientFilledButton({
    required this.onTap,
    required this.gradient,
    required this.padding,
    required this.shape,
    required this.textStyle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderRadius = shape.borderRadius.resolve(Directionality.of(context));
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: textStyle?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w600,
                  ) ??
                  TextStyle(
                    color: cs.onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
