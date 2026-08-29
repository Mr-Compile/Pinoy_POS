import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// An adaptive grid that picks its cross-axis count from the current
/// [LayoutClass] and applies consistent spacing.
class AppGrid extends StatelessWidget {
  final List<Widget> children;
  final int compactColumns;
  final int mediumColumns;
  final int expandedColumns;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  const AppGrid({
    super.key,
    required this.children,
    this.compactColumns = 2,
    this.mediumColumns = 3,
    this.expandedColumns = 4,
    this.childAspectRatio = 1.0,
    this.mainAxisSpacing = Spacing.md,
    this.crossAxisSpacing = Spacing.md,
    this.shrinkWrap = true,
    this.physics = const NeverScrollableScrollPhysics(),
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        final crossAxisCount = switch (layout) {
          LayoutClass.compact => compactColumns,
          LayoutClass.medium => mediumColumns,
          LayoutClass.expanded => expandedColumns,
        };

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: shrinkWrap,
          physics: physics,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
          padding: padding,
          children: children,
        );
      },
    );
  }
}
