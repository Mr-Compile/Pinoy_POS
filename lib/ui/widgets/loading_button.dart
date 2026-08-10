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
    final effectiveStyle = style ??
        (isDanger
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null);

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: effectiveStyle,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : child ??
              Text(
                label,
                style: const TextStyle(color: Colors.white),
              ),
    );
  }
}
