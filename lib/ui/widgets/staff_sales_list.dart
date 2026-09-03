import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';

/// A ranked list of staff members with their sales totals and mini bars.
///
/// The first row is highlighted as the top performer. Empty state is handled
/// by the caller; this widget should not be shown when [summaries] is empty.
class StaffSalesList extends StatelessWidget {
  final List<StaffSalesSummary> summaries;
  final String? valuePrefix;

  const StaffSalesList({
    super.key,
    required this.summaries,
    this.valuePrefix,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefix = valuePrefix ?? CurrencyUtils.symbol();
    final maxTotal = summaries.isEmpty
        ? 0.0
        : summaries.map((s) => s.totalSales).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < summaries.length; i++)
          _StaffSalesRow(
            summary: summaries[i],
            rank: i + 1,
            maxTotal: maxTotal,
            valuePrefix: prefix,
            isTop: i == 0,
            barColor: _rankColor(context, cs, i),
          ),
      ],
    );
  }

  Color _rankColor(BuildContext context, ColorScheme cs, int index) {
    final brightness = Theme.of(context).brightness;
    return switch (index) {
      0 => AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      1 => AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      2 => AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      _ => cs.primary,
    };
  }
}

class _StaffSalesRow extends StatelessWidget {
  final StaffSalesSummary summary;
  final int rank;
  final double maxTotal;
  final String valuePrefix;
  final bool isTop;
  final Color barColor;

  const _StaffSalesRow({
    required this.summary,
    required this.rank,
    required this.maxTotal,
    required this.valuePrefix,
    required this.isTop,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxTotal <= 0 ? 0.0 : summary.totalSales / maxTotal;
    final valueText =
        '$valuePrefix${summary.totalSales.toStringAsFixed(2)} · ${summary.transactionCount} sales';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isTop
                  ? AppSemanticColors.resolve(
                      AppSemanticColors.successContainer,
                      Theme.of(context).brightness)
                  : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: AppTypography.labelMedium(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isTop
                    ? AppSemanticColors.resolveOn(
                        AppSemanticColors.onSuccessContainer,
                        Theme.of(context).brightness)
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.fullName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isTop ? FontWeight.w600 : FontWeight.normal,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          SizedBox(
            width: 120,
            child: Text(
              valueText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
