import 'package:flutter/material.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveStyle = style ??
        (isDanger
            ? FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              )
            : null);

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: effectiveStyle,
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : child ?? Text(label),
    );
  }
}
