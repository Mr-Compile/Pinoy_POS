import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// One bar in a [MiniBarChart].
class BarChartPoint {
  final String label;
  final double value;

  const BarChartPoint({required this.label, required this.value});
}

/// A lightweight, dependency-free vertical bar chart for dashboard trends.
///
/// Renders bars scaled to the max value, with the bar color taken from
/// [ColorScheme.primary] (so it follows the semantic primary color).
/// The last bar (today) is drawn in [ColorScheme.tertiary] to highlight
/// the current period.
///
/// The caller is responsible for showing an empty-state message when
/// [points] is empty or all values are zero — this widget only draws
/// bars, never invents data.
class MiniBarChart extends StatelessWidget {
  final List<BarChartPoint> points;
  final String? valuePrefix;
  final double height;

  const MiniBarChart({
    super.key,
    required this.points,
    this.valuePrefix,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxValue = points.fold<double>(0.0, (m, p) => p.value > m ? p.value : m);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelHeight = 18.0;
          final valueHeight = 16.0;
          final barAreaHeight = height - labelHeight - valueHeight - Spacing.sm;
          final gap = Spacing.xs.toDouble();

          return Column(
            children: [
              // Bars
              SizedBox(
                height: barAreaHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < points.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == points.length - 1 ? 0 : gap),
                          child: _Bar(
                            value: points[i].value,
                            max: maxValue,
                            color: i == points.length - 1 ? cs.tertiary : cs.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xs),
              // Values
              SizedBox(
                height: valueHeight,
                child: Row(
                  children: [
                    for (int i = 0; i < points.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == points.length - 1 ? 0 : gap),
                          child: Text(
                            _formatValue(points[i].value),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // Labels
              SizedBox(
                height: labelHeight,
                child: Row(
                  children: [
                    for (int i = 0; i < points.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == points.length - 1 ? 0 : gap),
                          child: Text(
                            points[i].label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
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
  final double max;
  final Color color;

  const _Bar({required this.value, required this.max, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight * ratio;
        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: h < 2 && value > 0 ? 2 : h,
            decoration: BoxDecoration(
              color: value <= 0 ? cs.surfaceContainerHighest : color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        );
      },
    );
  }
}
