import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// A [FilledButton] with a built-in loading spinner.
///
/// This is a backwards-compatible wrapper around [AppButton].
class LoadingButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;
  final Widget? child;
  final ButtonStyle? style;
  final bool isDanger;
  final IconData? icon;
  final bool fullWidth;

  const LoadingButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.label = '',
    this.child,
    this.style,
    this.isDanger = false,
    this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isDanger) {
      return AppButton.destructive(
        onPressed: isLoading ? null : onPressed,
        label: label,
        icon: icon,
        isLoading: isLoading,
        fullWidth: fullWidth,
        child: child,
      );
    }
    return AppButton.filled(
      onPressed: isLoading ? null : onPressed,
      label: label,
      icon: icon,
      isLoading: isLoading,
      fullWidth: fullWidth,
      child: child,
    );
  }
}
