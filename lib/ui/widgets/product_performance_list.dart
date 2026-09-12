import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// Displays top products with rank, quantity sold, and revenue.
class ProductPerformanceList extends StatelessWidget {
  final List<TopProductResult> products;
  final Settings? storeInfo;

  const ProductPerformanceList({
    super.key,
    required this.products,
    this.storeInfo,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'No product data',
        message: 'No products were sold in this period.',
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (int i = 0; i < products.length; i++) ...[
          AppCard(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                _RankedProductThumb(
                  product: products[i],
                  rank: i + 1,
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        products[i].productName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${products[i].totalQuantity} sold',
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
                      CurrencyUtils.format(products[i].revenue, currency: _currency),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Revenue',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (i < products.length - 1) const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

/// Product thumbnail with the rank badge overlaid on the bottom-right
/// corner. Shows the product image when available; otherwise falls back
/// to a dynamic placeholder built from the product's initial.
class _RankedProductThumb extends StatelessWidget {
  final TopProductResult product;
  final int rank;

  const _RankedProductThumb({
    required this.product,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = product.productName.isNotEmpty
        ? product.productName[0].toUpperCase()
        : '?';

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              clipBehavior: Clip.antiAlias,
              child: AppImage(
                imagePath: product.imageUrl,
                borderRadius: AppRadius.md,
                placeholderIcon: Icons.inventory_2,
                placeholderIconSize: 20,
                placeholderBuilder: (context) => Center(
                  child: Text(
                    initial,
                    style: AppTypography.labelMedium(context).copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimary,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
