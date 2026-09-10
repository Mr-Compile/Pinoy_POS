import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';

/// Pagination footer mirroring the mockup `.pager` bar:
///
///   "1–10 of 24"        ‹  [1] [2] [3]  ›
///
/// Renders nothing when the result set fits on a single page. The page
/// buttons scroll horizontally when there are too many to fit.
class PaginationBar extends StatelessWidget {
  final int totalItems;
  final int currentPage;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const PaginationBar({
    super.key,
    required this.totalItems,
    required this.currentPage,
    required this.pageSize,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalPages = (totalItems / pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    final start = (currentPage - 1) * pageSize + 1;
    final end = math.min(currentPage * pageSize, totalItems);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$start–$end of $totalItems',
          style: AppTypography.bodySmall(context).copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: Icons.chevron_left,
                  onPressed: currentPage > 1
                      ? () => onPageChanged(currentPage - 1)
                      : null,
                  tooltip: 'Previous page',
                ),
                for (var i = 1; i <= totalPages; i++) ...[
                  const SizedBox(width: Spacing.xs),
                  i == currentPage
                      ? AppButton.filled(
                          label: '$i',
                          size: AppButtonSize.small,
                          onPressed: () => onPageChanged(i),
                        )
                      : AppButton.outlined(
                          label: '$i',
                          size: AppButtonSize.small,
                          color: AppButtonColor.neutral,
                          onPressed: () => onPageChanged(i),
                        ),
                ],
                const SizedBox(width: Spacing.xs),
                AppIconButton(
                  icon: Icons.chevron_right,
                  onPressed: currentPage < totalPages
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                  tooltip: 'Next page',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
