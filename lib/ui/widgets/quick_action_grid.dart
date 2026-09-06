import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// A responsive grid for dashboard quick actions.
///
/// Quick actions were previously laid out with `Wrap`, which produced
/// ragged rows of variable-width buttons and no control over column
/// count. This grid gives every action the same cell size and adapts the
/// column count to the available width via [LayoutClass]:
///
///   - compact (phone portrait, < 600): 2 columns
///   - medium (tablet / phone landscape, 600-899): 3 columns
///   - expanded (desktop / large tablet / web, >= 900): 4 columns
///
/// The grid is `shrinkWrap` + non-scrollable so it can be embedded inside
/// the dashboard's `SingleChildScrollView`.
class QuickActionGrid extends StatelessWidget {
  final List<Widget> children;

  const QuickActionGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        final (columns, aspectRatio) = switch (layout) {
          // Cells are icon-over-label tiles; the aspect ratio keeps them
          // wide and short so labels never clip on narrow screens and
          // tiles never grow into oversized cards on wide ones.
          LayoutClass.compact => (2, 1.8),
          LayoutClass.medium => (3, 2.2),
          LayoutClass.expanded => (4, 2.6),
        };

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Spacing.md,
          crossAxisSpacing: Spacing.md,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}
