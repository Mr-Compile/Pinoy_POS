import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/mini_bar_chart.dart';

/// Displays a sales trend as a vertical bar chart, switching between a compact
/// grid and a horizontally scrollable list depending on the number of points.
class SalesTrendChart extends StatelessWidget {
  final List<DailySalesPoint> trend;
  final ReportGroupBy groupBy;
  final SalesPeriod? period;
  final String? valuePrefix;

  const SalesTrendChart({
    super.key,
    required this.trend,
    required this.groupBy,
    this.period,
    this.valuePrefix,
  });

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty || _trendIsAllZero(trend)) {
      return const EmptyState(
        icon: Icons.bar_chart,
        title: 'No trend data',
        message: 'There are no sales to display for this period.',
      );
    }

    final points = trend.map(_toBarPoint).toList();
    final highlightIndex = _highlightIndex(points);
    final chart = points.length <= 12
        ? MiniBarChart(
            points: points,
            valuePrefix: valuePrefix,
            highlightIndex: highlightIndex,
          )
        : _ScrollableBarChart(
            points: points,
            valuePrefix: valuePrefix,
            highlightIndex: highlightIndex,
          );

    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        chart,
        const SizedBox(height: Spacing.sm),
        TrendChartLegend(
          normalColor: cs.primary,
          highlightColor: AppSemanticColors.resolve(AppSemanticColors.info, b),
        ),
      ],
    );
  }

  /// Highlights the bar with the highest sales. For daily periods this is the
  /// single selected day; for weekly/monthly it identifies the best day or week.
  int _highlightIndex(List<BarChartPoint> points) {
    if (points.isEmpty) return -1;
    var maxIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > points[maxIndex].value) {
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  bool _trendIsAllZero(List<DailySalesPoint> trend) {
    for (final point in trend) {
      if (point.total != 0.0 || point.count != 0) {
        return false;
      }
    }
    return true;
  }

  BarChartPoint _toBarPoint(DailySalesPoint point) {
    return BarChartPoint(
      label: _labelFor(point.date, groupBy, period),
      value: point.total,
    );
  }

  String _labelFor(DateTime date, ReportGroupBy groupBy, SalesPeriod? period) {
    if (period != null) {
      switch (period) {
        case SalesPeriod.daily:
          return '${date.month}/${date.day}';
        case SalesPeriod.weekly:
          return _weekdayShort(date.weekday);
        case SalesPeriod.monthly:
          final week = ((date.day - 1) / 7).floor() + 1;
          return 'Week $week';
        case SalesPeriod.custom:
          return '${date.month}/${date.day}';
      }
    }

    switch (groupBy) {
      case ReportGroupBy.day:
        return '${date.month}/${date.day}';
      case ReportGroupBy.week:
      case ReportGroupBy.month:
        return _monthName(date.month);
    }
  }

  String _weekdayShort(int weekday) {
    // Sunday = 7 in Dart, so map Sunday -> 0, Monday -> 1, ... Saturday -> 6.
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return names[weekday % 7];
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
  final int highlightIndex;

  const _ScrollableBarChart({
    required this.points,
    this.valuePrefix,
    this.highlightIndex = -1,
  });

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
                  height: 160,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Bar(
                        value: points[i].value,
                        maxValue: maxValue,
                        color: i == highlightIndex
                            ? AppSemanticColors.resolve(
                                AppSemanticColors.info,
                                Theme.of(context).brightness,
                              )
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
        final max =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 160.0;
        // Reserve space for the label/value text (approx. 36 px).
        final barArea = max - 36;
        if (barArea <= 0 || !barArea.isFinite) return const SizedBox.shrink();

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
                  top: Radius.circular(AppRadius.xs),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
