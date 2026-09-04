import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// Common button color roles. Use `primary` for primary CTAs and use
/// semantic colors only when the action meaning matches (e.g. green for
/// save / new sale, red for delete, amber for warnings).
enum AppButtonColor { primary, success, warning, info, error, neutral }

/// Common button variants used across the app.
enum AppButtonVariant { filled, outlined, text, elevated, destructive, quickAction, gradient }

/// Common button sizes. All sizes still respect the 48 dp touch target.
enum AppButtonSize { small, medium, large }

/// A unified, accessible button component.
///
/// Supports primary, secondary, outlined, text, elevated, destructive,
/// quick-action, and gradient variants, plus an optional loading state that
/// disables the button and swaps the label for a spinner. All sizes keep a
/// minimum 48 x 48 touch target.
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

  /// A full-width primary CTA with the login-style horizontal blue gradient.
  ///
  /// Use this for high-emphasis single actions (e.g. Sign In, Submit).
  const AppButton.gradient({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.color = AppButtonColor.primary,
  }) : variant = AppButtonVariant.gradient;

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

  /// A compact, vertically-stacked quick action used in Dashboard grids.
  ///
  /// The [icon] is rendered above the [label] and both automatically inherit
  /// the resolved foreground color for the chosen semantic [color].
  const AppButton.quickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.color = AppButtonColor.primary,
    this.isLoading = false,
  })  : child = null,
        size = AppButtonSize.medium,
        fullWidth = false,
        variant = AppButtonVariant.quickAction;

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

    final (mainColor, onMainColor) = _resolveColors(cs, theme.brightness, color);
    final labelColor = switch (variant) {
      AppButtonVariant.filled ||
      AppButtonVariant.elevated ||
      AppButtonVariant.destructive ||
      AppButtonVariant.quickAction ||
      AppButtonVariant.gradient =>
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
      AppButtonVariant.quickAction => _buildQuickAction(
          context,
          mainColor,
          onMainColor,
        ),
      AppButtonVariant.gradient => _buildGradientButton(
          context,
          cs,
          theme.brightness,
          padding,
          iconSize,
          onMainColor,
        ),
      AppButtonVariant.destructive => FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: mainColor,
            foregroundColor: onMainColor,
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

  /// Resolves the main and foreground colors for the chosen semantic role,
  /// adapting each tone to the current brightness.
  (Color, Color) _resolveColors(
    ColorScheme cs,
    Brightness brightness,
    AppButtonColor color,
  ) {
    return switch (color) {
      AppButtonColor.primary => (cs.primary, cs.onPrimary),
      AppButtonColor.success => (
          AppSemanticColors.resolve(AppSemanticColors.success, brightness),
          AppSemanticColors.resolveOn(AppSemanticColors.onSuccess, brightness)
        ),
      AppButtonColor.warning => (
          AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
          AppSemanticColors.resolveOn(AppSemanticColors.onWarning, brightness)
        ),
      AppButtonColor.info => (
          AppSemanticColors.resolve(AppSemanticColors.info, brightness),
          AppSemanticColors.resolveOn(AppSemanticColors.onInfo, brightness)
        ),
      AppButtonColor.error => (
          AppSemanticColors.resolve(AppSemanticColors.error, brightness),
          AppSemanticColors.resolveOn(AppSemanticColors.onError, brightness)
        ),
      AppButtonColor.neutral => (
          AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
          AppSemanticColors.resolveOn(AppSemanticColors.onNeutral, brightness)
        ),
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
    final disabledForeground = onMainColor.withValues(alpha: 0.38);
    final disabledBackground = color == AppButtonColor.primary
        ? null
        : mainColor.withValues(alpha: 0.12);

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: mainColor,
        foregroundColor: onMainColor,
        disabledForegroundColor: disabledForeground,
        disabledBackgroundColor: disabledBackground,
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
    final isPrimary = color == AppButtonColor.primary;

    if (isPrimary) {
      final disabledForeground = onMainColor.withValues(alpha: 0.38);
      return ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: onMainColor,
          disabledForegroundColor: disabledForeground,
          shadowColor: cs.primary.withValues(alpha: 0.15),
          elevation: isDark ? 2 : 1,
          shape: shape,
          padding: padding,
          minimumSize: const Size(48, 48),
          textStyle: textStyle,
        ),
        child: child,
      );
    }

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
        disabledForegroundColor: mainColor.withValues(alpha: 0.38),
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
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

  Widget _buildGradientButton(
    BuildContext context,
    ColorScheme cs,
    Brightness brightness,
    EdgeInsets padding,
    double iconSize,
    Color onMainColor,
  ) {
    final tapHandler = isLoading ? null : onPressed;
    final disabled = tapHandler == null && !isLoading;

    final height = switch (size) {
      AppButtonSize.small => 48.0,
      AppButtonSize.medium => 56.0,
      AppButtonSize.large => 64.0,
    };

    final effectivePadding = EdgeInsets.fromLTRB(
      padding.left,
      0,
      padding.right,
      0,
    );

    final loadingColor = onMainColor;
    final idleColor = disabled ? onMainColor.withValues(alpha: 0.38) : onMainColor;

    final labelWidget = isLoading
        ? Text(
            '...',
            textAlign: TextAlign.center,
            style: AppTypography.titleMediumBold(context).copyWith(
              color: loadingColor,
              fontWeight: FontWeight.bold,
            ),
          )
        : Text(
            label ?? '',
            textAlign: TextAlign.center,
            style: AppTypography.titleMediumBold(context).copyWith(
              color: idleColor,
              fontWeight: FontWeight.bold,
            ),
          );

    final content = isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: loadingColor,
                ),
              ),
              const SizedBox(width: 12),
              labelWidget,
            ],
          )
        : _buildIconLabel(
            child ?? labelWidget,
            icon,
            iconSize,
            idleColor,
          );

    const borderRadius = BorderRadius.all(Radius.circular(12));

    return Container(
      width: fullWidth ? double.infinity : null,
      height: height,
      constraints: const BoxConstraints(minWidth: 48),
      decoration: BoxDecoration(
        gradient: AppColors.loginGradient(brightness),
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        type: MaterialType.transparency,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: tapHandler,
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (disabled)
                Container(
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.12),
                    borderRadius: borderRadius,
                  ),
                ),
              Padding(
                padding: effectivePadding,
                child: Center(child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context,
    Color mainColor,
    Color onMainColor,
  ) {
    final tapHandler = isLoading ? null : onPressed;
    final disabledBackground = mainColor.withValues(alpha: 0.12);
    final disabledForeground = onMainColor.withValues(alpha: 0.38);

    return FilledButton(
      onPressed: tapHandler,
      style: FilledButton.styleFrom(
        backgroundColor: mainColor,
        foregroundColor: onMainColor,
        disabledBackgroundColor: disabledBackground,
        disabledForegroundColor: disabledForeground,
        iconColor: onMainColor,
        disabledIconColor: disabledForeground,
        iconSize: 28,
        overlayColor: onMainColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(64, 64),
        textStyle: AppTypography.labelMedium(context).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon!),
            const SizedBox(height: Spacing.xs),
            Text(
              label!,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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


