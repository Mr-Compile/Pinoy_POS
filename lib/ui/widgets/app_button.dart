import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// Common button variants used across the app.
enum AppButtonVariant { filled, outlined, text, elevated, destructive }

/// Common button sizes. All sizes still respect the 48 dp touch target.
enum AppButtonSize { small, medium, large }

/// A unified, accessible button component.
///
/// Supports primary, secondary, outlined, text, and destructive variants,
/// plus an optional loading state that disables the button and swaps the
/// label for a spinner. All sizes keep a minimum 48 x 48 touch target.
class AppButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;

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
  }) : variant = AppButtonVariant.destructive;

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

    final buttonChild = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: switch (variant) {
                AppButtonVariant.destructive => AppSemanticColors.onError,
                AppButtonVariant.filled ||
                AppButtonVariant.elevated => cs.onPrimary,
                _ => cs.primary,
              },
            ),
          )
        : _buildIconLabel(effectiveLabel, icon, iconSize);

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
        ),
      AppButtonVariant.elevated => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            shape: shape,
            padding: padding,
            minimumSize: const Size(48, 48),
            textStyle: textStyle,
          ),
          child: buttonChild,
        ),
      AppButtonVariant.outlined => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            shape: shape,
            padding: padding,
            minimumSize: const Size(48, 48),
            textStyle: textStyle,
          ),
          child: buttonChild,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
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

  Widget _buildFilledButton(
    BuildContext context,
    ColorScheme cs,
    RoundedRectangleBorder shape,
    EdgeInsets padding,
    TextStyle? textStyle,
    Widget child,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = AppColors.premiumButtonGradient(cs, theme.brightness);

    // Light mode or disabled/loading: use the standard FilledButton.
    if (isLoading || onPressed == null || !isDark || gradient == null) {
      return FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: shape,
          padding: padding,
          minimumSize: const Size(48, 48),
          textStyle: textStyle,
        ),
        child: child,
      );
    }

    // Dark mode filled button with subtle premium gradient.
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
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
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
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

  Widget _buildIconLabel(Widget label, IconData? icon, double iconSize) {
    if (icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize),
        const SizedBox(width: Spacing.sm),
        label,
      ],
    );
  }
}
