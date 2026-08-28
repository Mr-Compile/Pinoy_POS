import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
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
  String? _error;
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
      _error = null;
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
            labelText: 'Receipt, customer, or reference',
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
                      const DropdownMenuItem(
                          value: null, child: Text('All active')),
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

    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(title: 'My Sales'),
        body: LoadingState(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: const AppHeader(title: 'My Sales'),
        body: ErrorState(
          title: 'Error',
          message: _error,
          onRetry: _loadSales,
        ),
      );
    }

    final filtersActive = _selectedPaymentMethod != null ||
        _selectedPaymentStatus != null ||
        _searchQuery.isNotEmpty;

    final grouped = _groupByDate(_sales);

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
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final group = grouped[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8,
                            bottom: 8,
                            left: 4,
                          ),
                          child: Text(
                            group.label,
                            style: AppTypography.titleSmallBold(context)
                                .copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        ...group.sales.map((sale) => _buildSaleCard(
                              sale,
                              canVoid,
                              context,
                            )),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }

  List<_SalesGroup> _groupByDate(List<Sale> sales) {
    final groups = <String, List<Sale>>{};
    for (final sale in sales) {
      final key = _dateLabel(sale.createdAt);
      groups.putIfAbsent(key, () => []).add(sale);
    }
    return groups.entries
        .map((e) => _SalesGroup(label: e.key, sales: e.value))
        .toList();
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    final today = startOfDay(now);
    final saleDate = startOfDay(local);

    final diff = today.difference(saleDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      return [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ][local.weekday - 1];
    }
    return '${local.month}/${local.day}/${local.year}';
  }

  Widget _buildSaleCard(Sale sale, bool canVoid, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(sale.paymentStatus, cs);
    final time = _formatTime(sale.createdAt);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SaleDetailScreen(sale: sale),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sale #${sale.receiptNumber ?? sale.id}',
                          style: AppTypography.titleMediumBold(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₱${sale.totalAmount.toStringAsFixed(2)}',
                    style: AppTypography.titleMediumBold(context)
                        .copyWith(color: cs.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildPill(sale.paymentMethod, cs),
                  if (sale.customerName != null &&
                      sale.customerName!.isNotEmpty)
                    _buildPill(sale.customerName!, cs),
                  if (sale.referenceNumber != null &&
                      sale.referenceNumber!.isNotEmpty)
                    _buildPill('Ref: ${sale.referenceNumber}', cs),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Chip(
                    avatar: Icon(
                      _statusIcon(sale.paymentStatus),
                      size: 14,
                      color: statusColor,
                    ),
                    label: Text(
                      _statusLabel(sale.paymentStatus),
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                    side: BorderSide(color: statusColor),
                    backgroundColor: statusColor.withValues(alpha: 0.1),
                  ),
                  if (canVoid && sale.paymentStatus == 'confirmed')
                    LoadingButton(
                      isLoading: _isProcessing,
                      onPressed: () => _voidSale(sale),
                      label: 'Void',
                      isDanger: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Color _statusColor(String status, ColorScheme cs) {
    return switch (status) {
      'confirmed' => cs.primary,
      'pending' => cs.tertiary,
      'cancelled' || 'refunded' => cs.error,
      _ => cs.outline,
    };
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'confirmed' => Icons.check_circle,
      'pending' => Icons.hourglass_empty,
      'cancelled' || 'refunded' => Icons.cancel,
      _ => Icons.help,
    };
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return 'Unknown';
    return status[0].toUpperCase() + status.substring(1);
  }
}

class _SalesFilter {
  final String? paymentMethod;
  final String? paymentStatus;

  _SalesFilter(this.paymentMethod, this.paymentStatus);
}

class _SalesGroup {
  final String label;
  final List<Sale> sales;

  _SalesGroup({required this.label, required this.sales});
}
