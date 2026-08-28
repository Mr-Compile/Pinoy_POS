import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  List<Sale> _sales = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  String? _selectedPaymentMethod;
  String? _selectedPaymentStatus;
  String _searchQuery = '';

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
    });

    final salesService = ref.read(salesServiceProvider);
    final sales = await salesService.getFilteredSales(
      paymentMethod: _selectedPaymentMethod,
      paymentStatus: _selectedPaymentStatus,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      limit: 500,
    );

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
      AppDialogService.accessDenied(context);
      return;
    }

    final reason = await AppDialogService.voidSaleConfirm(context);

    if (reason != null && mounted) {
      setState(() => _isProcessing = true);

      try {
        final salesService = ref.read(salesServiceProvider);
        final success = await salesService.voidSale(sale.id!);
        if (mounted) {
          setState(() => _isProcessing = false);
          if (success) {
            await AppDialogService.success(
              context,
              title: 'Done',
              message: 'Sale voided successfully.',
            );
            _loadSales();
          } else {
            AppDialogService.error(
              context,
              title: 'Error',
              message: 'Failed to void sale.',
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Failed to void sale.',
          );
        }
      }
    }
  }

  Future<void> _showSearchDialog() async {
    _searchController.text = _searchQuery;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Sales'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Receipt or reference number',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_searchController.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _searchQuery = result;
      });
      await _loadSales();
    }
  }

  Future<void> _showFilterDialog() async {
    final methods = ['Cash', 'GCash', 'Card', 'Other'];
    const statuses = ['pending', 'confirmed', 'cancelled', 'refunded'];

    final result = await showDialog<_SalesFilter>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filter Sales'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    key: ValueKey(_selectedPaymentMethod),
                    initialValue: _selectedPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ...methods.map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m),
                          )),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => _selectedPaymentMethod = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(_selectedPaymentStatus),
                    initialValue: _selectedPaymentStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All active')),
                      ...statuses.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s[0].toUpperCase() + s.substring(1),
                            ),
                          )),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => _selectedPaymentStatus = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_SalesFilter(
                  _selectedPaymentMethod,
                  _selectedPaymentStatus,
                )),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPaymentMethod = result.paymentMethod;
        _selectedPaymentStatus = result.paymentStatus;
      });
      await _loadSales();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedPaymentMethod = null;
      _selectedPaymentStatus = null;
      _searchQuery = '';
    });
    _loadSales();
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canVoid = authNotifier.hasPermission('void_sales');
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: const AppHeader(title: 'My Sales'),
        body: const LoadingState(),
      );
    }

    final filtersActive = _selectedPaymentMethod != null ||
        _selectedPaymentStatus != null ||
        _searchQuery.isNotEmpty;

    return Scaffold(
      appBar: AppHeader(
        title: 'My Sales',
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _isProcessing ? null : _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _isProcessing ? null : _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isProcessing ? null : _loadSales,
          ),
        ],
      ),
      body: _sales.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long,
              title: 'No Sales',
              message: filtersActive
                  ? 'No sales match the selected filters.'
                  : 'Start selling to see sales history',
              action: filtersActive
                  ? FilledButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Filters'),
                    )
                  : null,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sales.length,
              itemBuilder: (context, index) {
                final sale = _sales[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sale #${sale.receiptNumber ?? sale.id}',
                          ),
                        ),
                        _buildStatusChip(sale, cs),
                      ],
                    ),
                    subtitle: Text(
                      '${sale.createdAt.toLocal().toString().split('.')[0]} · ${sale.paymentMethod}',
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
                          'PHP ${sale.totalAmount.toStringAsFixed(2)}',
                          style: AppTypography.titleMediumBold(context),
                        ),
                        if (canVoid && sale.paymentStatus == 'confirmed') ...[
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

  Widget _buildStatusChip(Sale sale, ColorScheme cs) {
    final status = sale.paymentStatus;
    Color color;
    IconData? icon;

    switch (status) {
      case 'confirmed':
        color = cs.primary;
        icon = Icons.check_circle;
        break;
      case 'pending':
        color = cs.tertiary;
        icon = Icons.hourglass_empty;
        break;
      case 'cancelled':
      case 'refunded':
        color = cs.error;
        icon = Icons.cancel;
        break;
      default:
        color = cs.outline;
        icon = null;
    }

    return Chip(
      avatar: icon != null ? Icon(icon, size: 14, color: color) : null,
      label: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: color, fontSize: 12),
      ),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

class _SalesFilter {
  final String? paymentMethod;
  final String? paymentStatus;

  _SalesFilter(this.paymentMethod, this.paymentStatus);
}
