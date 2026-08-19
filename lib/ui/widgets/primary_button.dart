import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// A primary call-to-action button that uses the active ColorScheme.
///
/// In **dark mode**, this button applies a subtle vertical gradient
/// derived from the user's accent color for a premium feel.
/// In **light mode**, it renders as a standard [FilledButton].
///
/// Use this for important primary actions:
/// - Save / Submit
/// - Add Product / Add User / Add Category
/// - Generate Report
/// - Checkout
///
/// For secondary actions (Cancel, Reset, etc.) use a regular
/// [TextButton] or [OutlinedButton] — do not use this widget.
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gradient = AppColors.premiumButtonGradient(colorScheme, theme.brightness);

    Widget buttonChild = child;
    if (isLoading) {
      buttonChild = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.onPrimary,
        ),
      );
    } else if (icon != null) {
      buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          child,
        ],
      );
    }

    // In dark mode with a gradient, use a Container wrapper to apply
    // the gradient as the button background.
    if (isDark && gradient != null && onPressed != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: colorScheme.onPrimary, size: 18),
                  child: buttonChild,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Light mode or disabled: standard FilledButton
    if (icon != null && !isLoading) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: child,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      child: buttonChild,
    );
  }
}
