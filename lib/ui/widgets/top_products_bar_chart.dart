import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/horizontal_bar_chart.dart';

/// A ranked horizontal bar chart of top-selling products by revenue.
class TopProductsBarChart extends StatelessWidget {
  final List<TopProductResult> products;
  final Settings? storeInfo;
  final double height;

  const TopProductsBarChart({
    super.key,
    required this.products,
    this.storeInfo,
    this.height = 220,
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

    final items = products
        .map((p) => HorizontalBarItem(
              label: p.productName,
              value: p.revenue,
              trailing: '${p.totalQuantity} sold',
            ))
        .toList();

    return HorizontalBarChart(
      items: items,
      valuePrefix: CurrencyUtils.symbol(currency: _currency),
      height: height,
    );
  }
}
