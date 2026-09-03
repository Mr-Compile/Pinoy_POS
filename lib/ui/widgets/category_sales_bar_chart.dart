import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/horizontal_bar_chart.dart';

/// A ranked horizontal bar chart of sales by category.
class CategorySalesBarChart extends StatelessWidget {
  final List<CategorySalesResult> categorySales;
  final Settings? storeInfo;
  final double height;

  const CategorySalesBarChart({
    super.key,
    required this.categorySales,
    this.storeInfo,
    this.height = 220,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    if (categorySales.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        title: 'No category data',
        message: 'No sales by category for this period.',
      );
    }

    final sorted = List<CategorySalesResult>.from(categorySales)
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    final items = sorted
        .map((c) => HorizontalBarItem(
              label: c.categoryName,
              value: c.totalSales,
              trailing: '${c.itemsSold} items',
            ))
        .toList();

    return HorizontalBarChart(
      items: items,
      valuePrefix: CurrencyUtils.symbol(currency: _currency),
      height: height,
    );
  }
}
