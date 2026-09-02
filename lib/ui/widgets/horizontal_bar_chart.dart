import 'package:flutter/material.dart';

/// One item in a [HorizontalBarChart].
class HorizontalBarItem {
  final String label;
  final double value;
  final String? trailing;

  const HorizontalBarItem({
    required this.label,
    required this.value,
    this.trailing,
  });
}

/// A ranked horizontal bar chart for top products, categories, etc.
///
/// Bars are sorted largest-first. Labels and optional trailing text are shown
/// next to each bar.
class HorizontalBarChart extends StatelessWidget {
  final List<HorizontalBarItem> items;
  final String? valuePrefix;
  final double height;

  const HorizontalBarChart({
    super.key,
    required this.items,
    this.valuePrefix,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = List<HorizontalBarItem>.from(items)
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = sorted.isEmpty
        ? 1.0
        : sorted.map((i) => i.value).reduce((a, b) => a > b ? a : b);

    if (sorted.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = sorted[index];
          final ratio = maxValue <= 0 ? 0.0 : (item.value / maxValue).clamp(0.0, 1.0);

          return Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 24,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: index == 0 ? cs.primary : cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: Text(
                  item.trailing ?? _formatValue(item.value),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
