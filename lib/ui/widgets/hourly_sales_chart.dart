import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/data/models/sales_by_hour_point.dart';

/// A horizontal, scrollable bar chart for sales by hour of day.
///
/// Empty hours (0-23) are filled with zero so the chart stays readable even
/// when the store is only busy at specific times.
class HourlySalesChart extends StatelessWidget {
  final List<SalesByHourPoint> points;
  final String valuePrefix;
  final double height;
  final double barWidth;

  const HourlySalesChart({
    super.key,
    required this.points,
    this.valuePrefix = '₱',
    this.height = 160,
    this.barWidth = 32,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filledPoints = _fillHours(points);
    final maxTotal = filledPoints
        .map((p) => p.total)
        .fold<double>(0.0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < filledPoints.length; i++)
              _HourBar(
                point: filledPoints[i],
                maxTotal: maxTotal,
                barWidth: barWidth,
                valuePrefix: valuePrefix,
                isCurrentHour: filledPoints[i].hour == DateTime.now().hour,
                barColor: i == filledPoints.length - 1 &&
                        filledPoints[i].hour == DateTime.now().hour
                    ? AppSemanticColors.resolve(
                        AppSemanticColors.info, Theme.of(context).brightness)
                    : cs.primary,
              ),
          ],
        ),
      ),
    );
  }

  List<SalesByHourPoint> _fillHours(List<SalesByHourPoint> input) {
    final byHour = {for (final p in input) p.hour: p};
    return [
      for (int h = 0; h < 24; h++)
        byHour[h] ?? SalesByHourPoint(hour: h, total: 0, count: 0),
    ];
  }
}

class _HourBar extends StatelessWidget {
  final SalesByHourPoint point;
  final double maxTotal;
  final double barWidth;
  final String valuePrefix;
  final bool isCurrentHour;
  final Color barColor;

  const _HourBar({
    required this.point,
    required this.maxTotal,
    required this.barWidth,
    required this.valuePrefix,
    required this.isCurrentHour,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxTotal <= 0 ? 0.0 : (point.total / maxTotal).clamp(0.0, 1.0);
    final isZero = point.total <= 0;

    return SizedBox(
      width: barWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatValue(point.total),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isZero ? cs.outline : cs.onSurface,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight * ratio;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: barWidth - 8,
                    height: isZero ? 2 : barHeight,
                    decoration: BoxDecoration(
                      color: isZero ? cs.surfaceContainerHighest : barColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      border: isCurrentHour
                          ? Border.all(color: cs.onSurface, width: 1.5)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _hourLabel(point.hour),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isCurrentHour ? cs.onSurface : cs.onSurfaceVariant,
                  fontWeight: isCurrentHour ? FontWeight.w600 : FontWeight.normal,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatValue(double v) {
    if (v >= 1000) {
      return '$valuePrefix${(v / 1000).toStringAsFixed(1)}k';
    }
    if (v > 0) {
      return '$valuePrefix${v.toStringAsFixed(0)}';
    }
    return '—';
  }

  String _hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h$period';
  }
}
