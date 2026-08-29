import 'package:flutter/material.dart';

/// Breakpoint values used for phone / tablet / desktop layouts.
class Breakpoints {
  Breakpoints._();

  /// Handset / compact window.
  static const double compact = 0;

  /// Tablet / medium window (side-by-side layouts become possible).
  static const double medium = 600;

  /// Expanded desktop / large tablet window (navigation rail extends).
  static const double expanded = 900;
}

/// The three layout buckets used by the app.
enum LayoutClass {
  /// Compact layout, typically a phone held in portrait.
  compact,

  /// Medium layout, typically a tablet or phone in landscape.
  medium,

  /// Expanded layout, typically a desktop or large tablet window.
  expanded,
}

/// Provides the current [LayoutClass] for the given [width].
LayoutClass layoutClassFor(double width) {
  if (width >= Breakpoints.expanded) return LayoutClass.expanded;
  if (width >= Breakpoints.medium) return LayoutClass.medium;
  return LayoutClass.compact;
}

extension LayoutClassExtension on LayoutClass {
  bool get isCompact => this == LayoutClass.compact;
  bool get isMedium => this == LayoutClass.medium;
  bool get isExpanded => this == LayoutClass.expanded;
  bool get isAtLeastMedium => this == LayoutClass.medium || this == LayoutClass.expanded;
  bool get isAtLeastExpanded => this == LayoutClass.expanded;
}

/// A widget that resolves the current [LayoutClass] and rebuilds a child
/// based on the width of the available space.
class LayoutClassBuilder extends StatelessWidget {
  final Widget? compact;
  final Widget? medium;
  final Widget? expanded;

  const LayoutClassBuilder({
    super.key,
    this.compact,
    this.medium,
    this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        return switch (layout) {
          LayoutClass.compact => compact ?? medium ?? expanded ?? const SizedBox.shrink(),
          LayoutClass.medium => medium ?? compact ?? expanded ?? const SizedBox.shrink(),
          LayoutClass.expanded => expanded ?? medium ?? compact ?? const SizedBox.shrink(),
        };
      },
    );
  }
}

/// A widget that passes the current [LayoutClass] to a builder. Prefer this
/// when the child tree is large and you want to switch logic rather than
/// replace the whole subtree.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, LayoutClass layout) builder;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        return builder(context, layout);
      },
    );
  }
}

/// Convenience for switching a single value by layout class.
T layoutValue<T>({
  required BuildContext context,
  required T compact,
  T? medium,
  T? expanded,
}) {
  final width = MediaQuery.of(context).size.width;
  final layout = layoutClassFor(width);
  return switch (layout) {
    LayoutClass.compact => compact,
    LayoutClass.medium => medium ?? compact,
    LayoutClass.expanded => expanded ?? medium ?? compact,
  };
}
