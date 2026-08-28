import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/ui/screens/receipt_screen.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppHeader(title: 'Payment Successful', showBackButton: false),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, size: 64, color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Payment Successful',
                      style: AppTypography.headlineSmallSemibold(context)
                          .copyWith(color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(height: 24),
                    _buildRow('Amount', '₱${sale.totalAmount.toStringAsFixed(2)}'),
                    if (sale.change > 0)
                      _buildRow('Change', '₱${sale.change.toStringAsFixed(2)}'),
                    _buildRow('Method', sale.paymentMethod),
                    if (sale.referenceNumber != null && sale.referenceNumber!.isNotEmpty)
                      _buildRow('Reference', sale.referenceNumber!),
                    if (sale.customerName != null && sale.customerName!.isNotEmpty)
                      _buildRow('Customer', sale.customerName!),
                    _buildRow(
                      'Status',
                      sale.paymentStatus[0].toUpperCase() +
                          sale.paymentStatus.substring(1),
                    ),
                    _buildRow(
                      'Receipt #',
                      sale.receiptNumber ?? sale.id?.toString() ?? '—',
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SaleDetailScreen(sale: sale),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View Sale Details'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReceiptScreen(sale: sale),
                  ),
                );
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('View / Download Receipt'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                // Pop back to the POS tab (root of the navigation stack).
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('New Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
