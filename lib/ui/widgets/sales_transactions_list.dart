import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

/// Confirmed sales for the selected period.
class SalesTransactionsList extends StatelessWidget {
  final List<Sale> sales;
  final Settings? storeInfo;
  final Map<int, String>? staffNames;
  final void Function(Sale sale)? onTap;

  const SalesTransactionsList({
    super.key,
    required this.sales,
    this.storeInfo,
    this.staffNames,
    this.onTap,
  });

  String get _currency => storeInfo?.currency ?? 'PHP';

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No sales',
        message: 'There are no confirmed sales for this period.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sales.length; i++) ...[
          _SaleRow(
            sale: sales[i],
            currency: _currency,
            staffNames: staffNames,
            onTap: onTap,
          ),
          if (i < sales.length - 1) const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final String currency;
  final Map<int, String>? staffNames;
  final void Function(Sale sale)? onTap;

  const _SaleRow({
    required this.sale,
    required this.currency,
    this.staffNames,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateTime = _formatDateTime(sale.createdAt);
    final title = sale.receiptNumber ?? 'Sale #${sale.id}';
    final cashierName = staffNames?[sale.userId] ?? 'User ${sale.userId}';
    final subtitle = '$dateTime • Cashier: $cashierName';

    return AppListItem(
      title: title,
      subtitle: subtitle,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer,
        child: Icon(
          Icons.receipt_outlined,
          size: 18,
          color: cs.onPrimaryContainer,
        ),
      ),
      trailing: Text(
        '$currency ${sale.totalAmount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      statusLabel: _statusLabel(sale.paymentStatus),
      statusColor: _statusColor(
        sale.paymentStatus,
        Theme.of(context).brightness,
      ),
      chips: [
        AppStatusChip(
          label: sale.paymentMethod,
          color: cs.primary,
          filled: false,
        ),
      ],
      onTap: onTap == null ? null : () => onTap!(sale),
    );
  }

  String _formatDateTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final amPm = d.hour < 12 ? 'AM' : 'PM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.month}/${d.day}/${d.year} $hour:$minute $amPm';
  }

  String? _statusLabel(String status) {
    if (status == 'confirmed') return 'Paid';
    if (status == 'pending') return 'Pending';
    if (status == 'cancelled' || status == 'refunded') return 'Cancelled';
    return null;
  }

  Color _statusColor(String status, Brightness brightness) {
    switch (status) {
      case 'confirmed':
        return AppSemanticColors.resolve(AppSemanticColors.success, brightness);
      case 'pending':
        return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
      case 'cancelled':
      case 'refunded':
        return AppSemanticColors.resolve(AppSemanticColors.error, brightness);
      default:
        return AppSemanticColors.resolve(
          AppSemanticColors.neutral,
          brightness,
        );
    }
  }
}
