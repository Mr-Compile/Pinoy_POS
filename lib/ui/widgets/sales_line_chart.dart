import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// A line chart for a sales trend, supporting hourly, daily, weekly or monthly
/// buckets and rendering correctly in light and dark themes.
class SalesLineChart extends StatelessWidget {
  final List<DailySalesPoint> points;
  final ReportGroupBy groupBy;
  final String? valuePrefix;
  final double height;

  const SalesLineChart({
    super.key,
    required this.points,
    required this.groupBy,
    this.valuePrefix,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: 'No trend data',
        message: 'There are no sales to display for this period.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final sorted = List<DailySalesPoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));
    final maxValue = sorted.map((p) => p.total).reduce((a, b) => a > b ? a : b);

    final spots = List<FlSpot>.generate(
      sorted.length,
      (i) => FlSpot(i.toDouble(), sorted[i].total),
    );

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue > 0 ? maxValue / 4 : 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: _bottomTitles(sorted, cs),
            ),
            leftTitles: AxisTitles(
              sideTitles: _leftTitles(maxValue, cs),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant),
              left: BorderSide(color: cs.outlineVariant),
            ),
          ),
          lineTouchData: _touchData(sorted, cs),
          minY: 0,
          maxY: maxValue > 0 ? maxValue * 1.15 : 1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: cs.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: sorted.length <= 31,
                getDotPainter: (spot, x, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: cs.primary,
                  strokeColor: cs.surface,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: cs.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineTouchData _touchData(List<DailySalesPoint> sorted, ColorScheme cs) {
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => cs.surfaceContainerHigh,
        tooltipBorder: BorderSide(color: cs.outlineVariant),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final point = sorted[spot.x.toInt()];
            return LineTooltipItem(
              '${_labelFor(point.date)}\n${_formatMoney(point.total)}',
              TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            );
          }).toList();
        },
      ),
    );
  }

  SideTitles _bottomTitles(List<DailySalesPoint> sorted, ColorScheme cs) {
    final step = _labelStep(sorted.length);
    return SideTitles(
      showTitles: true,
      interval: step.toDouble(),
      reservedSize: 30,
      getTitlesWidget: (value, meta) {
        final index = value.toInt();
        if (index < 0 || index >= sorted.length) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            _labelFor(sorted[index].date),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
          ),
        );
      },
    );
  }

  SideTitles _leftTitles(double maxValue, ColorScheme cs) {
    final interval = maxValue > 0 ? maxValue / 4 : 1.0;
    return SideTitles(
      showTitles: true,
      reservedSize: 44,
      interval: interval,
      getTitlesWidget: (value, meta) {
        if (value < 0) return const SizedBox.shrink();
        return Text(
          _formatAxis(value),
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 10,
          ),
          maxLines: 1,
        );
      },
    );
  }

  int _labelStep(int count) {
    if (count <= 12) return 1;
    if (count <= 24) return 2;
    if (count <= 48) return 4;
    if (count <= 90) return 7;
    return (count / 8).ceil();
  }

  String _labelFor(DateTime date) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final amPm = date.hour < 12 ? 'AM' : 'PM';
        return '$hour$amPm';
      case ReportGroupBy.day:
      case ReportGroupBy.week:
        return '${date.month}/${date.day}';
      case ReportGroupBy.month:
        const names = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return names[date.month - 1];
    }
  }

  String _formatAxis(double value) {
    if (value >= 1000) {
      return '${valuePrefix ?? ''}${(value / 1000).toStringAsFixed(1)}k';
    }
    return '${valuePrefix ?? ''}${value.toStringAsFixed(0)}';
  }

  String _formatMoney(double value) {
    if (value >= 1000) {
      return '${valuePrefix ?? ''}${(value / 1000).toStringAsFixed(1)}k';
    }
    return '${valuePrefix ?? ''}${value.toStringAsFixed(0)}';
  }
}

/// A dual-line chart comparing the current period to the previous period.
class SalesComparisonChart extends StatelessWidget {
  final List<DailySalesPoint> current;
  final List<DailySalesPoint> previous;
  final ReportGroupBy groupBy;
  final String? valuePrefix;
  final double height;

  const SalesComparisonChart({
    super.key,
    required this.current,
    required this.previous,
    required this.groupBy,
    this.valuePrefix,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (current.isEmpty && previous.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: 'No comparison data',
        message: 'There is not enough data to compare periods.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final currentSorted = List<DailySalesPoint>.from(current)
      ..sort((a, b) => a.date.compareTo(b.date));

    final allValues = [
      ...current.map((p) => p.total),
      ...previous.map((p) => p.total),
    ];
    final maxValue = allValues.isEmpty
        ? 1.0
        : allValues.reduce((a, b) => a > b ? a : b);

    final currentSpots = List<FlSpot>.generate(
      currentSorted.length,
      (i) => FlSpot(i.toDouble(), currentSorted[i].total),
    );

    final previousSpots = List<FlSpot>.generate(
      previous.length,
      (i) => FlSpot(i.toDouble(), previous[i].total),
    );

    return Column(
      children: [
        _Legend(
          items: [
            _LegendItem(
              label: 'Current period',
              color: cs.primary,
            ),
            _LegendItem(
              label: 'Previous period',
              color: cs.tertiary,
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxValue > 0 ? maxValue / 4 : 1,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: _bottomTitles(currentSorted, cs),
                ),
                leftTitles: AxisTitles(
                  sideTitles: _leftTitles(maxValue, cs),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant),
                  left: BorderSide(color: cs.outlineVariant),
                ),
              ),
              lineTouchData: _touchData(currentSorted, previous, cs),
              minY: 0,
              maxY: maxValue > 0 ? maxValue * 1.15 : 1,
              lineBarsData: [
                LineChartBarData(
                  spots: currentSpots,
                  isCurved: true,
                  color: cs.primary,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: current.length <= 31,
                    getDotPainter: (spot, x, bar, index) => FlDotCirclePainter(
                      radius: 3,
                      color: cs.primary,
                      strokeColor: cs.surface,
                      strokeWidth: 1.5,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: cs.primary.withValues(alpha: 0.08),
                  ),
                ),
                LineChartBarData(
                  spots: previousSpots,
                  isCurved: true,
                  color: cs.tertiary,
                  barWidth: 2,
                  dashArray: [5, 5],
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: previous.length <= 31,
                    getDotPainter: (spot, x, bar, index) => FlDotCirclePainter(
                      radius: 2.5,
                      color: cs.tertiary,
                      strokeColor: cs.surface,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineTouchData _touchData(
    List<DailySalesPoint> currentSorted,
    List<DailySalesPoint> previous,
    ColorScheme cs,
  ) {
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => cs.surfaceContainerHigh,
        tooltipBorder: BorderSide(color: cs.outlineVariant),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final isCurrent = spot.barIndex == 0;
            final points = isCurrent ? currentSorted : previous;
            final index = spot.x.toInt().clamp(0, points.length - 1);
            final point = points[index];
            return LineTooltipItem(
              '${isCurrent ? 'Current' : 'Previous'}\n${_formatMoney(point.total)}',
              TextStyle(
                color: isCurrent ? cs.primary : cs.tertiary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            );
          }).toList();
        },
      ),
    );
  }

  SideTitles _bottomTitles(List<DailySalesPoint> sorted, ColorScheme cs) {
    final step = _labelStep(sorted.length);
    return SideTitles(
      showTitles: true,
      interval: step.toDouble(),
      reservedSize: 30,
      getTitlesWidget: (value, meta) {
        final index = value.toInt();
        if (index < 0 || index >= sorted.length) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            _labelFor(sorted[index].date),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
          ),
        );
      },
    );
  }

  SideTitles _leftTitles(double maxValue, ColorScheme cs) {
    final interval = maxValue > 0 ? maxValue / 4 : 1.0;
    return SideTitles(
      showTitles: true,
      reservedSize: 44,
      interval: interval,
      getTitlesWidget: (value, meta) {
        if (value < 0) return const SizedBox.shrink();
        return Text(
          _formatAxis(value),
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 10,
          ),
          maxLines: 1,
        );
      },
    );
  }

  int _labelStep(int count) {
    if (count <= 12) return 1;
    if (count <= 24) return 2;
    if (count <= 48) return 4;
    if (count <= 90) return 7;
    return (count / 8).ceil();
  }

  String _labelFor(DateTime date) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final amPm = date.hour < 12 ? 'AM' : 'PM';
        return '$hour$amPm';
      case ReportGroupBy.day:
      case ReportGroupBy.week:
        return '${date.month}/${date.day}';
      case ReportGroupBy.month:
        const names = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return names[date.month - 1];
    }
  }

  String _formatAxis(double value) {
    if (value >= 1000) {
      return '${valuePrefix ?? ''}${(value / 1000).toStringAsFixed(1)}k';
    }
    return '${valuePrefix ?? ''}${value.toStringAsFixed(0)}';
  }

  String _formatMoney(double value) {
    if (value >= 1000) {
      return '${valuePrefix ?? ''}${(value / 1000).toStringAsFixed(1)}k';
    }
    return '${valuePrefix ?? ''}${value.toStringAsFixed(0)}';
  }
}

class _Legend extends StatelessWidget {
  final List<_LegendItem> items;

  const _Legend({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(left: Spacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;

  const _LegendItem({required this.label, required this.color});
}
