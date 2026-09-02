import 'package:flutter/material.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_list.dart';
import 'package:pinoy_pos/ui/widgets/payment_method_chart.dart';

/// Displays payment method totals. Uses a donut when there are few methods,
/// otherwise falls back to a ranked list so labels remain readable.
class PaymentBreakdownView extends StatelessWidget {
  final List<PaymentBreakdown> breakdown;
  final double? grandTotal;
  final Settings? storeInfo;

  const PaymentBreakdownView({
    super.key,
    required this.breakdown,
    this.grandTotal,
    this.storeInfo,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  String get _currencySymbol {
    if (_currency == 'PHP') return '₱';
    return _currency;
  }

  @override
  Widget build(BuildContext context) {
    final total = grandTotal ??
        breakdown.fold<double>(0.0, (sum, p) => sum + p.total);

    if (breakdown.isEmpty) {
      return const PaymentBreakdownList(
        breakdown: [],
      );
    }

    // Donut works well for up to 6 slices; beyond that a list is clearer.
    if (breakdown.length <= 6) {
      return PaymentMethodChart(
        breakdown: breakdown,
        grandTotal: total,
        valuePrefix: _currencySymbol,
      );
    }

    return PaymentBreakdownList(
      breakdown: breakdown,
      grandTotal: total,
      storeInfo: storeInfo,
    );
  }
}
