import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/kpi_card.dart';

/// Four summary KPI cards for the Sales Analytics screen.
class SalesSummaryCards extends StatelessWidget {
  final SalesAnalytics analytics;
  final Settings? storeInfo;

  const SalesSummaryCards({
    super.key,
    required this.analytics,
    this.storeInfo,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    final comparison = analytics.comparison;

    return KpiGrid(
      children: [
        _buildCard(
          context,
          label: 'Total Sales',
          icon: Icons.payments_outlined,
          iconColor: AppSemanticColors.resolve(
            AppSemanticColors.success,
            Theme.of(context).brightness,
          ),
          value: _formatMoney(analytics.totalSales),
          subtitle: _changeText(
            comparison.totalChangePercent(analytics.totalSales),
            'vs previous period',
          ),
          tier: KpiCardTier.primary,
        ),
        _buildCard(
          context,
          label: 'Transactions',
          icon: Icons.receipt_outlined,
          iconColor: Theme.of(context).colorScheme.primary,
          value: analytics.transactionCount.toString(),
          subtitle: _changeText(
            comparison.transactionCountChangePercent(analytics.transactionCount),
            'vs previous period',
          ),
          tier: KpiCardTier.secondary,
        ),
        _buildCard(
          context,
          label: 'Average Sale',
          icon: Icons.trending_up,
          iconColor: Theme.of(context).colorScheme.tertiary,
          value: _formatMoney(analytics.averageTransaction),
          subtitle: _changeText(
            comparison.averageTransactionChangePercent(analytics.averageTransaction),
            'vs previous period',
          ),
          tier: KpiCardTier.secondary,
        ),
        _buildCard(
          context,
          label: 'Items Sold',
          icon: Icons.shopping_basket_outlined,
          iconColor: AppSemanticColors.resolve(
            AppSemanticColors.info,
            Theme.of(context).brightness,
          ),
          value: analytics.itemsSold.toString(),
          subtitle: _changeText(
            comparison.itemsSoldChangePercent(analytics.itemsSold),
            'vs previous period',
          ),
          tier: KpiCardTier.secondary,
        ),
      ],
    );
  }

  KpiCard _buildCard(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color iconColor,
    required String value,
    required String subtitle,
    KpiCardTier tier = KpiCardTier.secondary,
  }) {
    return KpiCard(
      label: label,
      value: value,
      icon: icon,
      iconColor: iconColor,
      subtitle: subtitle,
      tier: tier,
    );
  }

  String _formatMoney(double value) {
    return CurrencyUtils.format(value, currency: _currency);
  }

  String _changeText(double? percent, String suffix) {
    if (percent == null) return 'No previous data • $suffix';
    final isUp = percent >= 0;
    final arrow = isUp ? '▲' : '▼';
    final pct = percent.abs().toStringAsFixed(1);
    return '$arrow $pct% $suffix';
  }
}
