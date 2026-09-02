import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';

/// A donut chart showing payment-method composition for a period.
///
/// Displays percentage of total sales and a legend with method name and amount.
/// When there are no payments, an empty state is rendered.
class PaymentMethodChart extends StatelessWidget {
  final List<PaymentBreakdown> breakdown;
  final double? grandTotal;
  final String? valuePrefix;
  final double size;

  const PaymentMethodChart({
    super.key,
    required this.breakdown,
    this.grandTotal,
    this.valuePrefix,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = grandTotal ??
        breakdown.fold<double>(0.0, (sum, p) => sum + p.total);
    final active = breakdown.where((p) => p.total > 0).toList();

    if (active.isEmpty) {
      return SizedBox(
        height: size + Spacing.lg,
        child: Center(
          child: Text(
            'No payment data',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    final colors = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
      cs.primaryContainer,
      cs.tertiaryContainer,
      cs.secondaryContainer,
      cs.errorContainer,
    ];

    final sections = active.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final pct = total <= 0 ? 0.0 : p.total / total;
      final color = colors[i % colors.length];

      return PieChartSectionData(
        color: color,
        value: p.total,
        radius: size / 2 - 16,
        title: '${(pct * 100).toStringAsFixed(0)}%',
        titleStyle: TextStyle(
          color: _contrastColor(cs, color),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
    }).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.25,
              sections: sections,
              pieTouchData: PieTouchData(enabled: false),
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < active.length; i++) ...[
                _LegendItem(
                  color: colors[i % colors.length],
                  label: active[i].method,
                  value: _formatMoney(active[i].total),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _contrastColor(ColorScheme colorScheme, Color color) {
    final brightness = color.computeLuminance();
    return brightness > 0.5 ? colorScheme.surface : colorScheme.onSurface;
  }

  String _formatMoney(double v) {
    return '${valuePrefix ?? ''}${v.toStringAsFixed(2)}';
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
