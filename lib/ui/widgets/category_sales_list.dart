import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// Displays ranked sales by category.
class CategorySalesList extends StatelessWidget {
  final List<CategorySalesResult> categorySales;
  final Settings? storeInfo;
  final int limit;

  const CategorySalesList({
    super.key,
    required this.categorySales,
    this.storeInfo,
    this.limit = 8,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = (List<CategorySalesResult>.from(categorySales)
          ..sort((a, b) => b.totalSales.compareTo(a.totalSales)))
        .take(limit)
        .toList();
    final maxTotal = sorted.isEmpty
        ? 0.0
        : sorted.map((c) => c.totalSales).reduce((a, b) => a > b ? a : b);

    if (sorted.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        title: 'No category data',
        message: 'No sales by category for this period.',
      );
    }

    return Column(
      children: [
        for (int i = 0; i < sorted.length; i++) ...[
          AppCard(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: cs.primaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sorted[i].categoryName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sorted[i].itemsSold} items · ${sorted[i].transactionCount} sales',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyUtils.format(sorted[i].totalSales, currency: _currency),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxTotal <= 0
                        ? 0.0
                        : (sorted[i].totalSales / maxTotal).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.tertiary),
                  ),
                ),
              ],
            ),
          ),
          if (i < sorted.length - 1) const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}
