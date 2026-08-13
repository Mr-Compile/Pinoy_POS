import 'package:flutter/material.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';

class SaleDetailScreen extends StatefulWidget {
  final Sale sale;

  const SaleDetailScreen({super.key, required this.sale});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final SalesService _salesService = SalesService();
  List<SaleItem> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _salesService.getSaleItems(widget.sale.id!);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load sale items';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Receipt #${widget.sale.receiptNumber ?? widget.sale.id}'),
      ),
      body: _isLoading
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  title: 'Error',
                  message: _error,
                  onRetry: _loadItems,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pinoy POS',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Receipt #${widget.sale.receiptNumber ?? widget.sale.id}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              widget.sale.createdAt.toLocal().toString().split('.')[0],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Item', style: Theme.of(context).textTheme.titleSmall),
                                Text('Qty • Price • Total',
                                    style: Theme.of(context).textTheme.titleSmall),
                              ],
                            ),
                            const Divider(),
                            ..._items.map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Product #${item.productId}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${item.quantity} • ₱${item.unitPrice.toStringAsFixed(2)} • ₱${item.totalPrice.toStringAsFixed(2)}',
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          children: [
                            _buildRow('Subtotal', '₱${widget.sale.totalAmount.toStringAsFixed(2)}'),
                            const Divider(),
                            _buildRow('Cash Received', '₱${widget.sale.cashReceived.toStringAsFixed(2)}'),
                            const Divider(),
                            _buildRow('Change', '₱${widget.sale.change.toStringAsFixed(2)}'),
                            const Divider(),
                            _buildRow(
                              'Total',
                              '₱${widget.sale.totalAmount.toStringAsFixed(2)}',
                              isTotal: true,
                            ),
                          ],
                        ),
                      ),
                      if (widget.sale.notes != null && widget.sale.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              Text(widget.sale.notes!),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Thank you for your purchase!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
                : Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: isTotal
                ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
