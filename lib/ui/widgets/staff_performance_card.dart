import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';

/// Highlights the top-performing staff member and a compact runner-up list.
///
/// Use this on owner/admin dashboards as a quick performance summary. The
/// full ranked list lives in [StaffSalesList].
class StaffPerformanceCard extends StatelessWidget {
  final List<StaffSalesSummary> summaries;
  final String valuePrefix;
  final int runnerUpCount;

  const StaffPerformanceCard({
    super.key,
    required this.summaries,
    this.valuePrefix = '₱',
    this.runnerUpCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (summaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final top = summaries.first;
    final runnerUps = summaries.skip(1).take(runnerUpCount).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events,
                color: AppSemanticColors.resolve(
                  AppSemanticColors.success,
                  Theme.of(context).brightness,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Top Performer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            top.fullName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            '$valuePrefix${top.totalSales.toStringAsFixed(2)} · ${top.transactionCount} sales',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          if (runnerUps.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            ...runnerUps.asMap().entries.map((entry) {
              final s = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  children: [
                    Text(
                      '${entry.key + 2}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        s.fullName,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$valuePrefix${s.totalSales.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
