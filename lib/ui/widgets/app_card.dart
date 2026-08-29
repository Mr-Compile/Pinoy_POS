import 'package:flutter/material.dart';

/// Visual style of an [AppCard].
enum AppCardVariant { elevated, filled, outlined }

/// A reusable, accessible card with consistent radius, padding, and tap
/// feedback. Use [AppCardVariant.filled] for grouped content,
/// [AppCardVariant.elevated] for stand-alone call-outs, and
/// [AppCardVariant.outlined] for selectable items.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final double? elevation;
  final AppCardVariant variant;
  final double borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.elevation,
    this.variant = AppCardVariant.elevated,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveRadius = BorderRadius.circular(borderRadius);

    final Color? effectiveColor = switch (variant) {
      AppCardVariant.elevated => color,
      AppCardVariant.filled => color ?? cs.surfaceContainerLowest,
      AppCardVariant.outlined => color ?? cs.surface,
    };

    final double effectiveElevation = switch (variant) {
      AppCardVariant.elevated => elevation ?? 1,
      AppCardVariant.filled => elevation ?? 0,
      AppCardVariant.outlined => elevation ?? 0,
    };

    final shape = switch (variant) {
      AppCardVariant.elevated || AppCardVariant.filled => RoundedRectangleBorder(
          borderRadius: effectiveRadius,
        ),
      AppCardVariant.outlined => RoundedRectangleBorder(
          borderRadius: effectiveRadius,
          side: BorderSide(color: cs.outlineVariant),
        ),
    };

    final card = Card(
      color: effectiveColor,
      elevation: effectiveElevation,
      shape: shape,
      margin: margin,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: effectiveRadius,
        child: card,
      );
    }

    return card;
  }
}
