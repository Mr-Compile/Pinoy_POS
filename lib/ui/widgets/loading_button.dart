import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// A [FilledButton] with a built-in loading spinner.
///
/// In **dark mode**, non-danger buttons get a subtle accent-derived
/// gradient for a premium feel (see [AppColors.premiumButtonGradient]).
/// Danger buttons always use the semantic error color (no gradient).
class LoadingButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;
  final Widget? child;
  final ButtonStyle? style;
  final bool isDanger;

  const LoadingButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.label = '',
    this.child,
    this.style,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Danger buttons always use semantic error color — no gradient.
    if (isDanger) {
      return FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: style ??
            FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
        child: _buildChild(colorScheme),
      );
    }

    // Custom style override — respect it as-is.
    if (style != null) {
      return FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: _buildChild(colorScheme),
      );
    }

    // Dark mode + enabled: apply premium gradient.
    final gradient = AppColors.premiumButtonGradient(colorScheme, theme.brightness);
    if (isDark && gradient != null && !isLoading && onPressed != null) {
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
                child: child ?? Text(label),
              ),
            ),
          ),
        ),
      );
    }

    // Light mode, disabled, or loading: standard FilledButton.
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: _buildChild(colorScheme),
    );
  }

  Widget _buildChild(ColorScheme colorScheme) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.onPrimary,
        ),
      );
    }
    return child ?? Text(label);
  }
}
