import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final SalesService _salesService = SalesService();
  List<Sale> _sales = [];
  bool _isLoading = true;
  bool _isProcessing = false;

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

  Future<void> _voidSale(Sale sale) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('void_sales')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final reason = await EnhancedDialogs.showVoidSaleDialog(
      context: context,
    );

    if (reason != null && mounted) {
      setState(() {
        _isProcessing = true;
      });

      try {
        final success = await _salesService.voidSale(sale.id!);
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          if (success) {
            showSuccessSnackbar(context, 'Sale voided successfully');
            _loadSales();
          } else {
            showErrorSnackbar(context, 'Failed to void sale');
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          showErrorSnackbar(context, 'Failed to void sale');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canVoid = authNotifier.hasPermission('void_sales');

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
            onPressed: _isProcessing ? null : _loadSales,
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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SaleDetailScreen(sale: sale),
                        ),
                      );
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₱${sale.totalAmount.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (canVoid) ...[
                          const SizedBox(width: 8),
                          LoadingButton(
                            isLoading: _isProcessing,
                            onPressed: () => _voidSale(sale),
                            label: 'Void',
                            isDanger: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
