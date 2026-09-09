import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// A responsive primary Create/Add action that follows the global Pinoy POS
/// design rule:
///
///   - Phone portrait (compact width + portrait) → floating action button.
///   - Every other layout (tablet, desktop, phone landscape) → labeled button
///     inside the screen's content toolbar via [CrudToolbar].
///
/// Only one of the two representations is visible at a time, so a screen
/// never shows duplicate primary create controls. The global [AppHeader]
/// must never host the primary module CRUD action.
///
/// Permission gating is the caller's responsibility: construct this object
/// only when the current role may create records, e.g.
/// ```dart
/// final createAction = canEdit
///     ? ResponsiveCreateAction(label: 'Add Product', icon: Icons.add,
///         onPressed: _showProductDialog)
///     : null;
/// ```
///
/// Use [contentAction] inside a [CrudToolbar] and [fab] for
/// [Scaffold.floatingActionButton]. Both return `null` when the action should
/// not be shown, so the consuming screen can safely pass the result directly.
/// Use [contentBottomClearance] to pad the bottom of scrollable content so
/// the last item is never hidden behind the FAB.
class ResponsiveCreateAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Accessible tooltip. Defaults to [label].
  final String? tooltip;

  /// Semantic color role for the action. [AppButtonColor.primary] keeps the
  /// default theme FAB colors; other roles resolve to their semantic
  /// background/foreground pair (e.g. warning for bulk-reset actions).
  final AppButtonColor color;

  const ResponsiveCreateAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = AppButtonColor.primary,
  });

  /// Extra bottom padding for scrollable CRUD content so the last list item
  /// clears the FAB (56dp FAB + margins + breathing room).
  static const double fabClearance = 88;

  /// Below this width a compact circular FAB is used instead of an extended
  /// one so the FAB does not crowd very narrow screens.
  static const double extendedFabMinWidth = 360;

  /// True when the action should be a FAB: compact width AND portrait
  /// orientation. Compact landscape and every wider layout use the content
  /// toolbar button instead.
  bool isFabLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return layoutClassFor(size.width).isCompact &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
  }

  /// Bottom padding to add to scrollable CRUD content. Returns
  /// [fabClearance] while the FAB layout is active, else 0.
  double contentBottomClearance(BuildContext context) =>
      isFabLayout(context) ? fabClearance : 0;

  /// A primary, labeled button for the CRUD content toolbar.
  ///
  /// Returns `null` while the FAB layout is active so the caller can use a
  /// null-aware spread or conditional list literal. A `null` [onPressed]
  /// still renders a disabled button, which is useful for actions that
  /// become temporarily unavailable (e.g., while a background operation
  /// is in flight).
  Widget? contentAction(BuildContext context) {
    if (isFabLayout(context)) return null;

    return AppButton.filled(
      size: AppButtonSize.small,
      icon: icon,
      label: label,
      onPressed: onPressed,
      color: color,
    );
  }

  /// A floating action button for compact portrait layouts.
  ///
  /// Returns `null` on medium+ layouts and on compact landscape. Extended
  /// when the screen is wide enough, compact circular on very narrow
  /// screens. Scaffold handles safe-area, bottom-navigation, and keyboard
  /// insets automatically.
  Widget? fab(BuildContext context) {
    if (!isFabLayout(context)) return null;

    final width = MediaQuery.sizeOf(context).width;
    final effectiveTooltip = tooltip ?? label;
    final (backgroundColor, foregroundColor) = _fabColors(context);
    // Per-label hero tag prevents duplicate-hero errors when navigating
    // between CRUD screens that both show a FAB.
    final heroTag = 'crud_fab_$label';

    if (width >= extendedFabMinWidth) {
      return FloatingActionButton.extended(
        heroTag: heroTag,
        onPressed: onPressed,
        tooltip: effectiveTooltip,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return FloatingActionButton(
      heroTag: heroTag,
      onPressed: onPressed,
      tooltip: effectiveTooltip,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Icon(icon),
    );
  }

  /// Semantic FAB colors for non-primary actions; `null`s keep the
  /// [FloatingActionButtonThemeData] colors for the primary role.
  (Color?, Color?) _fabColors(BuildContext context) {
    if (color == AppButtonColor.primary) return (null, null);

    final brightness = Theme.of(context).brightness;
    final (accent, onAccent) = switch (color) {
      AppButtonColor.success => (
          AppSemanticColors.success,
          AppSemanticColors.onSuccess
        ),
      AppButtonColor.warning => (
          AppSemanticColors.warning,
          AppSemanticColors.onWarning
        ),
      AppButtonColor.info => (AppSemanticColors.info, AppSemanticColors.onInfo),
      AppButtonColor.error => (
          AppSemanticColors.error,
          AppSemanticColors.onError
        ),
      AppButtonColor.neutral => (
          AppSemanticColors.neutral,
          AppSemanticColors.onNeutral
        ),
      AppButtonColor.purple => (
          AppSemanticColors.purple,
          AppSemanticColors.onPurple
        ),
      _ => (AppSemanticColors.primary, AppSemanticColors.onPrimary),
    };
    return (
      AppSemanticColors.resolve(accent, brightness),
      AppSemanticColors.resolveOn(onAccent, brightness),
    );
  }
}

/// The standard CRUD content toolbar:
///
/// ```text
/// medium+ : [ Search ] [ filter controls... ] [ pinned ] [ + Add ]
/// compact : [ Search ]
///           [ filter controls... (scroll) ] [ pinned ] [ + Add ]
/// ```
///
/// [search] takes the leading flexible space on medium+ layouts and is
/// capped at [maxSearchWidth]. [controls] are scrollable filters (chips,
/// dropdowns). [pinnedControls] sit at the trailing edge (sort menus,
/// refresh buttons) and never scroll away. [primaryAction] is the
/// [ResponsiveCreateAction.contentAction] result — it renders at the end of
/// the toolbar on medium+ and on compact landscape, and is `null` on
/// compact portrait where the action is a FAB.
///
/// The toolbar intentionally renders only what it is given: callers decide
/// which controls a module needs.
class CrudToolbar extends StatelessWidget {
  /// Search field shown first. Omit for toolbars without search.
  final Widget? search;

  /// Filter controls (chips, dropdowns) shown in a horizontally scrollable
  /// group between the search field and the pinned/primary controls.
  final List<Widget> controls;

  /// Controls pinned to the trailing edge (sort menus, refresh buttons).
  final List<Widget> pinnedControls;

  /// The module's primary action, typically
  /// `createAction?.contentAction(context)`. Always trailing.
  final Widget? primaryAction;

  final EdgeInsetsGeometry padding;

  /// Maximum width of [search] on medium+ layouts.
  final double maxSearchWidth;

  const CrudToolbar({
    super.key,
    this.search,
    this.controls = const [],
    this.pinnedControls = const [],
    this.primaryAction,
    this.padding = const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.md,
      Spacing.lg,
      Spacing.sm,
    ),
    this.maxSearchWidth = 480,
  });

  List<Widget> _join(List<Widget> children) {
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: Spacing.sm),
        children[i],
      ],
    ];
  }

  Widget _scrollableControls() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _join(controls),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTrailing =
        controls.isNotEmpty || pinnedControls.isNotEmpty || primaryAction != null;
    if (search == null && !hasTrailing) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              layoutClassFor(constraints.maxWidth).isCompact;

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?search,
                if (hasTrailing) ...[
                  if (search != null) const SizedBox(height: Spacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: controls.isEmpty
                            ? const SizedBox.shrink()
                            : _scrollableControls(),
                      ),
                      for (final control in pinnedControls) ...[
                        const SizedBox(width: Spacing.sm),
                        control,
                      ],
                      if (primaryAction != null) ...[
                        const SizedBox(width: Spacing.sm),
                        primaryAction!,
                      ],
                    ],
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              if (search != null)
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxSearchWidth),
                    child: search!,
                  ),
                ),
              if (controls.isNotEmpty) ...[
                const SizedBox(width: Spacing.md),
                Expanded(child: _scrollableControls()),
              ] else if (hasTrailing)
                const Spacer(),
              for (final control in pinnedControls) ...[
                const SizedBox(width: Spacing.sm),
                control,
              ],
              if (primaryAction != null) ...[
                const SizedBox(width: Spacing.md),
                primaryAction!,
              ],
            ],
          );
        },
      ),
    );
  }
}
