import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// Displays staff sales performance for owner/managers.
class StaffPerformanceList extends StatelessWidget {
  final List<StaffSalesSummary> staff;
  final Settings? storeInfo;

  const StaffPerformanceList({
    super.key,
    required this.staff,
    this.storeInfo,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No staff sales',
        message: 'No staff sales recorded for this period.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final maxTotal = staff.isEmpty
        ? 0.0
        : staff.map((s) => s.totalSales).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (int i = 0; i < staff.length; i++) ...[
          AppCard(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: cs.primaryContainer,
                      child: Text(
                        staff[i].fullName.isNotEmpty
                            ? staff[i].fullName.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staff[i].fullName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${staff[i].transactionCount} sales',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_currency ${staff[i].totalSales.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Avg $_currency ${staff[i].averageTransaction.toStringAsFixed(2)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxTotal <= 0
                        ? 0.0
                        : (staff[i].totalSales / maxTotal).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ],
            ),
          ),
          if (i < staff.length - 1) const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}
