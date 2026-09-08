import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// A responsive primary Create/Add action that follows the global Pinoy POS
/// design rule:
///
///   - Phone portrait / compact layouts  → floating action button (FAB).
///   - Tablet / medium+ layouts          → labeled button in the AppBar.
///
/// Only one of the two representations is visible at a time, so a screen
/// never shows duplicate primary create controls.
///
/// Use [appBarAction] for the screen [AppHeader.actions] list and [fab] for
/// [Scaffold.floatingActionButton]. Both return `null` when the action should
/// not be shown, so the consuming screen can safely pass the result directly.
class ResponsiveCreateAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const ResponsiveCreateAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  bool _isCompact(BuildContext context) =>
      layoutClassFor(MediaQuery.of(context).size.width).isCompact;

  /// A primary, labeled button for tablet/desktop AppBars.
  ///
  /// Returns `null` on compact (phone) layouts so the caller can use a
  /// null-aware spread or conditional list literal. A `null` [onPressed]
  /// still renders a disabled button, which is useful for actions that
  /// become temporarily unavailable (e.g., while a background operation
  /// is in flight).
  Widget? appBarAction(BuildContext context) {
    if (_isCompact(context)) return null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: AppButton.filled(
        size: AppButtonSize.small,
        icon: icon,
        label: label,
        onPressed: onPressed,
      ),
    );
  }

  /// A floating action button for phone portrait layouts.
  ///
  /// Returns `null` on medium+ (tablet/desktop) layouts. A `null`
  /// [onPressed] renders a disabled FAB, which is useful for temporarily
  /// unavailable actions.
  Widget? fab(BuildContext context) {
    if (!_isCompact(context)) return null;

    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
