import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
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
    this.size = 130,
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

    final brightness = Theme.of(context).brightness;
    final colors = [
      cs.primary,
      AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      AppSemanticColors.resolve(AppSemanticColors.purple, brightness),
      AppSemanticColors.resolve(AppSemanticColors.error, brightness),
      AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
    ];

    // fl_chart measures section radius outward from centerSpaceRadius, so the
    // pie's true outer radius is centerSpaceRadius + section.radius. Keeping
    // that sum below size/2 stops the pie from painting over the legend.
    final centerSpaceRadius = size * 0.27;
    final ringRadius = size / 2 - centerSpaceRadius - Spacing.xs;

    final sections = active.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final pct = total <= 0 ? 0.0 : p.total / total;
      final color = colors[i % colors.length];

      return PieChartSectionData(
        color: color,
        value: p.total,
        radius: ringRadius,
        title: '${(pct * 100).toStringAsFixed(0)}%',
        titleStyle: TextStyle(
          color: _contrastColor(context, cs, color),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
    }).toList();

    final chart = SizedBox(
      width: size,
      height: size,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: centerSpaceRadius,
          sections: sections,
          pieTouchData: PieTouchData(enabled: false),
        ),
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < active.length; i++) ...[
          _LegendItem(
            color: colors[i % colors.length],
            label: active[i].method,
            count: active[i].count,
            value: _formatMoney(active[i].total),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // On narrow containers the legend stacks below the chart instead of
        // being squeezed beside it.
        final stacked = constraints.maxWidth.isFinite &&
            constraints.maxWidth < size + 170;
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: chart),
              const SizedBox(height: Spacing.md),
              SizedBox(width: double.infinity, child: legend),
            ],
          );
        }
        return Row(
          children: [
            chart,
            const SizedBox(width: Spacing.md),
            Expanded(child: legend),
          ],
        );
      },
    );
  }

  Color _contrastColor(BuildContext context, ColorScheme colorScheme, Color color) {
    return AppSemanticColors.contrastFor(
      color,
      Theme.of(context).brightness,
      threshold: 0.4,
    );
  }

  String _formatMoney(double v) {
    return '${valuePrefix ?? ''}${v.toStringAsFixed(2)}';
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
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
          const SizedBox(width: 6),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
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
