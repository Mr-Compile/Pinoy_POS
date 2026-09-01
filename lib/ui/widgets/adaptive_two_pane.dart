import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// A two-pane layout that shows [listPane] and [detailPane] side-by-side on
/// medium+ screens and lets the user pick a detail on compact screens.
///
/// On compact screens, only [listPane] is visible. When [selectedId] is not
/// null, [detailPane] is pushed via [Navigator] (or nested, depending on the
/// caller). This widget only handles the side-by-side layout; navigation to a
/// detail screen must be implemented by the caller.
///
/// The [detailPane] is always rebuilt when [selectedId] changes, so callers
/// should keep detail state in a provider or in a `ValueKey(selectedId)`.
class AdaptiveTwoPane extends StatelessWidget {
  final Widget listPane;
  final Widget detailPane;
  final Object? selectedId;
  final double detailPaneFlex;
  final double listPaneFlex;

  const AdaptiveTwoPane({
    super.key,
    required this.listPane,
    required this.detailPane,
    this.selectedId,
    this.detailPaneFlex = 2,
    this.listPaneFlex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        if (layout == LayoutClass.compact) {
          return listPane;
        }

        final gap = layout == LayoutClass.medium ? Spacing.md : Spacing.lg;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: listPaneFlex.toInt(),
              child: listPane,
            ),
            SizedBox(width: gap),
            Expanded(
              flex: detailPaneFlex.toInt(),
              child: detailPane,
            ),
          ],
        );
      },
    );
  }
}
