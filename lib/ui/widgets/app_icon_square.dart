import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// A rounded-square icon container used for list badges and semantic icons.
///
/// Matches the `.isquare` pattern from the mockups: a 38x38 rounded badge
/// with a tinted background and a centered icon.
class AppIconSquare extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final double borderRadius;
  final double iconSizeFactor;

  const AppIconSquare({
    super.key,
    required this.icon,
    this.size = 38,
    this.backgroundColor,
    this.iconColor,
    this.borderRadius = AppRadius.icon,
    this.iconSizeFactor = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        icon,
        size: size * iconSizeFactor,
        color: iconColor ?? cs.onSurfaceVariant,
      ),
    );
  }
}
