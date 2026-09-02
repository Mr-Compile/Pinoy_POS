import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/mini_bar_chart.dart';

/// Displays a sales trend as a vertical bar chart, switching between a compact
/// grid and a horizontally scrollable list depending on the number of points.
class SalesTrendChart extends StatelessWidget {
  final List<DailySalesPoint> trend;
  final ReportGroupBy groupBy;
  final String? valuePrefix;

  const SalesTrendChart({
    super.key,
    required this.trend,
    required this.groupBy,
    this.valuePrefix,
  });

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart,
        title: 'No trend data',
        message: 'There are no sales to display for this period.',
      );
    }

    final points = trend.map(_toBarPoint).toList();

    if (points.length <= 12) {
      return MiniBarChart(points: points, valuePrefix: valuePrefix);
    }

    return _ScrollableBarChart(points: points, valuePrefix: valuePrefix);
  }

  BarChartPoint _toBarPoint(DailySalesPoint point) {
    return BarChartPoint(
      label: _labelFor(point.date, groupBy),
      value: point.total,
    );
  }

  String _labelFor(DateTime date, ReportGroupBy groupBy) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final amPm = date.hour < 12 ? 'AM' : 'PM';
        return '$hour$amPm';
      case ReportGroupBy.day:
        return '${date.month}/${date.day}';
      case ReportGroupBy.week:
      case ReportGroupBy.month:
        return _monthName(date.month);
    }
  }

  String _monthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month - 1];
  }
}

/// Horizontally scrollable bar chart for many data points.
class _ScrollableBarChart extends StatelessWidget {
  final List<BarChartPoint> points;
  final String? valuePrefix;

  const _ScrollableBarChart({required this.points, this.valuePrefix});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const barWidth = 28.0;
    const gap = 6.0;
    final maxValue = points.fold<double>(0.0, (m, p) => p.value > m ? p.value : m);

    return SizedBox(
      height: 160,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < points.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? Spacing.md : 0,
                  right: i == points.length - 1 ? Spacing.md : gap,
                ),
                child: SizedBox(
                  width: barWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Bar(
                        value: points[i].value,
                        maxValue: maxValue,
                        color: i == points.length - 1
                            ? cs.tertiary
                            : cs.primary,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        _formatValue(points[i].value),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        points[i].label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double v) {
    if (valuePrefix == null) {
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
      return v.toStringAsFixed(0);
    }
    if (v >= 1000) return '$valuePrefix${(v / 1000).toStringAsFixed(1)}k';
    return '$valuePrefix${v.toStringAsFixed(0)}';
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxValue;
  final Color color;

  const _Bar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxHeight;
        // Reserve space for the label/value text (approx. 36 px).
        final barArea = max - 36;
        if (barArea <= 0) return const SizedBox.shrink();

        final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

        return SizedBox(
          height: barArea,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              height: (barArea * ratio).clamp(2.0, barArea),
              decoration: BoxDecoration(
                color: value <= 0 ? cs.surfaceContainerHighest : color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
