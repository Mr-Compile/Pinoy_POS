import 'package:flutter/material.dart';

/// A 48 x 48 accessible icon button with consistent ripple, tooltip, and
/// optional selected / filled state.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final Color? color;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = color ??
        (selected ? cs.primary : cs.onSurfaceVariant);

    final button = IconButton(
      icon: Icon(icon, size: size, color: foreground),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: selected ? cs.primaryContainer : null,
        foregroundColor: foreground,
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}
