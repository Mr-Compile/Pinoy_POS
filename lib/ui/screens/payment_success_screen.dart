import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/ui/screens/receipt_screen.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// Success screen shown after a sale is persisted. It displays the payment
/// summary and gives the cashier quick actions to view the receipt, sale
/// detail, or start a new sale.
class PaymentSuccessScreen extends StatelessWidget {
  final Sale sale;

  const PaymentSuccessScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final successColor =
        AppSemanticColors.resolve(AppSemanticColors.success, brightness);
    final onSuccessColor =
        AppSemanticColors.resolve(AppSemanticColors.onSuccess, brightness);
    final onSuccessMuted = onSuccessColor.withValues(alpha: 0.85);

    return Scaffold(
      appBar: const AppHeader(
        title: 'Payment Successful',
        showBackButton: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    color: successColor,
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(Spacing.md),
                            decoration: BoxDecoration(
                              color: onSuccessColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              size: 48,
                              color: onSuccessColor,
                            ),
                          ),
                          const SizedBox(height: Spacing.lg),
                          Text(
                            'Payment Successful',
                            style: AppTypography.headlineSmallSemibold(
                              context,
                            ).copyWith(color: onSuccessColor),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.sm),
                          Text(
                            '${sale.paymentMethod} transaction saved successfully.',
                            style: AppTypography.bodyLarge(context).copyWith(
                              color: onSuccessMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xl),
                          Container(
                            padding: const EdgeInsets.all(Spacing.lg),
                            decoration: BoxDecoration(
                              color: onSuccessColor.withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.control),
                            ),
                            child: Column(
                              children: [
                                _buildSummaryRow(
                                  context,
                                  'Total',
                                  CurrencyUtils.format(sale.totalAmount),
                                  onSuccessColor,
                                  isBold: true,
                                ),
                                if (sale.change > 0)
                                  _buildSummaryRow(
                                    context,
                                    'Change',
                                    CurrencyUtils.format(sale.change),
                                    onSuccessColor,
                                  ),
                                _buildSummaryRow(
                                  context,
                                  'Method',
                                  sale.paymentMethod,
                                  onSuccessColor,
                                ),
                                if (sale.referenceNumber != null &&
                                    sale.referenceNumber!.isNotEmpty)
                                  _buildSummaryRow(
                                    context,
                                    'Reference',
                                    sale.referenceNumber!,
                                    onSuccessColor,
                                  ),
                                if (sale.customerName != null &&
                                    sale.customerName!.isNotEmpty)
                                  _buildSummaryRow(
                                    context,
                                    'Customer',
                                    sale.customerName!,
                                    onSuccessColor,
                                  ),
                                _buildSummaryRow(
                                  context,
                                  'Receipt #',
                                  sale.receiptNumber ??
                                      sale.id?.toString() ??
                                      '—',
                                  onSuccessColor,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Spacing.xl),
                          FilledButton.icon(
                            onPressed: () {
                              // Pop back to the POS tab (root of the navigation stack).
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: onSuccessColor,
                              foregroundColor: successColor,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: const Text('New Sale'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  AppButton.outlined(
                    fullWidth: true,
                    icon: Icons.receipt_long_outlined,
                    label: 'View Sale Details',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SaleDetailScreen(sale: sale),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: Spacing.md),
                  AppButton.outlined(
                    fullWidth: true,
                    icon: Icons.print_outlined,
                    label: 'View / Download Receipt',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptScreen(sale: sale),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMedium(context).copyWith(
              color: color.withValues(alpha: 0.9),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMediumSemibold(context).copyWith(
              color: color,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
