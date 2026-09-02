import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/peak_sales_period.dart';

/// Displays the peak sales hour and day for a period.
class PeakSalesCard extends StatelessWidget {
  final PeakSalesPeriod peak;

  const PeakSalesCard({
    super.key,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _PeakItem(
            icon: Icons.schedule,
            label: 'Peak Hour',
            value: peak.peakHourLabel,
            subValue: peak.peakHour != null
                ? '${peak.peakHourTransactions} sales'
                : null,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: _PeakItem(
            icon: Icons.calendar_today,
            label: 'Peak Day',
            value: peak.peakDayLabel,
            subValue: peak.peakDay != null
                ? '${peak.peakDayTransactions} sales'
                : null,
            color: cs.tertiary,
          ),
        ),
      ],
    );
  }
}

class _PeakItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final Color color;

  const _PeakItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Spacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              subValue!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
