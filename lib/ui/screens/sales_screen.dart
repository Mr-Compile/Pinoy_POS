import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final SalesService _salesService = SalesService();
  List<Sale> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
    });

    final sales = await _salesService.getSales();

    if (mounted) {
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSales,
          ),
        ],
      ),
      body: _sales.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long,
              title: 'No Sales',
              message: 'Start selling to see sales history',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sales.length,
              itemBuilder: (context, index) {
                final sale = _sales[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('Sale #${sale.receiptNumber ?? sale.id}'),
                    subtitle: Text(
                      sale.createdAt.toLocal().toString().split('.')[0],
                    ),
                    trailing: Text(
                      '₱${sale.totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
