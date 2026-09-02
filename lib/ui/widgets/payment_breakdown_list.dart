import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// Displays payment-method totals as a progress-bar list.
class PaymentBreakdownList extends StatelessWidget {
  final List<PaymentBreakdown> breakdown;
  final double? grandTotal;
  final Settings? storeInfo;

  const PaymentBreakdownList({
    super.key,
    required this.breakdown,
    this.grandTotal,
    this.storeInfo,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    final total = grandTotal ??
        breakdown.fold<double>(0.0, (sum, p) => sum + p.total);

    if (breakdown.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No payment data',
        message: 'No confirmed sales for this period.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final sorted = List<PaymentBreakdown>.from(breakdown)
      ..sort((a, b) => b.total.compareTo(a.total));

    final colors = [
      cs.primary,
      AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      AppSemanticColors.resolve(AppSemanticColors.error, brightness),
      cs.secondary,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sorted.length; i++) ...[
          _PaymentMethodRow(
            breakdown: sorted[i],
            total: total,
            color: colors[i % colors.length],
            currency: _currency,
          ),
          if (i < sorted.length - 1) const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  final PaymentBreakdown breakdown;
  final double total;
  final Color color;
  final String currency;

  const _PaymentMethodRow({
    required this.breakdown,
    required this.total,
    required this.color,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (breakdown.total / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                breakdown.method,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Text(
              '$currency ${breakdown.total.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            SizedBox(
              width: 60,
              child: Text(
                '${breakdown.count}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
