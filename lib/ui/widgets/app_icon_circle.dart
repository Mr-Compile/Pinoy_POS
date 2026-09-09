import 'package:flutter/material.dart';

/// A circular icon container used for status, avatar, and empty states.
///
/// Matches the `.icircle` pattern from the mockups: a round badge with a
/// subtle or semantic background, an optional border, and a centered icon.
class AppIconCircle extends StatelessWidget {
  final IconData icon;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? borderColor;
  final double borderWidth;

  const AppIconCircle({
    super.key,
    required this.icon,
    this.radius = 20,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
    this.borderWidth = 0,
  });

  /// Small 30×30 circle used for inline status and list badges.
  const AppIconCircle.small({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
    this.borderWidth = 0,
  })  : radius = 15;

  /// Medium 40×40 circle used for headers and list leading icons.
  const AppIconCircle.medium({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
    this.borderWidth = 0,
  })  : radius = 20;

  /// Large 56×56 circle used for auth and fullscreen empty states.
  const AppIconCircle.large({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
    this.borderWidth = 0,
  })  : radius = 28;

  /// Fullscreen 80×80 circle used for access denied and empty states.
  const AppIconCircle.fullscreen({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
    this.borderWidth = 0,
  })  : radius = 40;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveRadius = borderWidth > 0 ? radius - borderWidth : radius;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: borderColor,
      ),
      padding: borderWidth > 0 ? EdgeInsets.all(borderWidth) : EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? cs.surfaceContainerHigh,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: effectiveRadius * 0.7,
          color: iconColor ?? cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
