import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';

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
  ReportingPeriod _selectedPeriod = ReportingPeriod.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;

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

  ReportingPeriodBounds _periodBounds() => periodBoundsFor(
        _selectedPeriod,
        customStart: _customStart,
        customEnd: _customEnd,
      );

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final bounds = _periodBounds();
    final salesService = ref.read(salesServiceProvider);
    final sales = await salesService.getFilteredSales(
      start: bounds.start,
      end: bounds.end,
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

  void _onPeriodSelected(ReportingPeriod period) {
    if (period == _selectedPeriod) return;

    setState(() {
      _selectedPeriod = period;
      if (period != ReportingPeriod.custom) {
        _customStart = null;
        _customEnd = null;
      }
    });
    _loadSales();
  }

  void _onCustomRange(DateTimeRange range) {
    setState(() {
      _selectedPeriod = ReportingPeriod.custom;
      _customStart = range.start;
      _customEnd = range.end;
    });
    _loadSales();
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
      useRootNavigator: true,
      builder: (context) => AppDialog(
        type: AppDialogType.info,
        title: 'Search Sales',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(null),
          ),
          AppDialogAction(
            label: 'Search',
            isPrimary: true,
            onPressed: (context) => Navigator.of(context, rootNavigator: true)
                .pop(_searchController.text.trim()),
          ),
        ],
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Receipt, customer, or reference',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
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

    // Local copies so that changing a dropdown and then cancelling does not
    // mutate the screen's filter state.
    var selectedMethod = _selectedPaymentMethod;
    var selectedStatus = _selectedPaymentStatus;

    final result = await showDialog<_SalesFilter>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AppDialog(
          type: AppDialogType.info,
          title: 'Filter Sales',
          actions: [
            AppDialogAction(
              label: 'Cancel',
              onPressed: (context) =>
                  Navigator.of(context, rootNavigator: true).pop(null),
            ),
            AppDialogAction(
              label: 'Apply',
              isPrimary: true,
              onPressed: (context) =>
                  Navigator.of(context, rootNavigator: true).pop(
                _SalesFilter(selectedMethod, selectedStatus),
              ),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  key: const ValueKey('filter_payment_method'),
                  initialValue: selectedMethod,
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
                      setDialogState(() => selectedMethod = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('filter_payment_status'),
                  initialValue: selectedStatus,
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
                      setDialogState(() => selectedStatus = value),
                ),
              ],
            ),
          ),
        ),
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
      _selectedPeriod = ReportingPeriod.thisMonth;
      _customStart = null;
      _customEnd = null;
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
        _searchQuery.isNotEmpty ||
        _selectedPeriod != ReportingPeriod.thisMonth;

    final grouped = _groupByDate(_sales);
    final totalAmount = _sales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );

    return Scaffold(
      appBar: AppHeader(
        title: 'My Sales',
        actions: [
          AppIconButton(
            icon: Icons.search,
            onPressed: _isProcessing ? null : _showSearchDialog,
            tooltip: 'Search',
          ),
          AppIconButton(
            icon: Icons.filter_list,
            onPressed: _isProcessing ? null : _showFilterDialog,
            tooltip: 'Filters',
          ),
          AppIconButton(
            icon: Icons.refresh,
            onPressed: _isProcessing ? null : _loadSales,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _buildPeriodHeader(context),
              const Divider(height: 1),
              _buildSummaryCard(context, totalAmount, _sales.length),
              const SizedBox(height: Spacing.sm),
              Expanded(
                child: _sales.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long,
                        title: 'No Sales',
                        message: filtersActive
                            ? 'No sales match the selected filters.'
                            : 'Start selling to see sales history',
                        action: filtersActive
                            ? AppButton.filled(
                                onPressed: _clearFilters,
                                icon: Icons.clear,
                                label: 'Clear Filters',
                                size: AppButtonSize.small,
                              )
                            : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: grouped.length,
                        itemBuilder: (context, index) {
                          final group = grouped[index];
                          final groupTotal = group.sales.fold<double>(
                            0,
                            (sum, sale) => sum + sale.totalAmount,
                          );
                          return AppSection(
                            title: group.label,
                            subtitle:
                                '${group.sales.length} sale${group.sales.length == 1 ? '' : 's'} · ₱${groupTotal.toStringAsFixed(2)}',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: group.sales
                                  .map((sale) =>
                                      _buildSaleCard(sale, canVoid, context))
                                  .toList(),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodHeader(BuildContext context) {
    final bounds = _periodBounds();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatPeriodLabel(bounds),
                  style: AppTypography.titleMediumBold(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedPaymentMethod != null ||
                  _selectedPaymentStatus != null ||
                  _searchQuery.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          PeriodSelector(
            selected: _selectedPeriod,
            onSelected: _onPeriodSelected,
            customStart: _customStart,
            customEnd: _customEnd,
            onCustomRange: _onCustomRange,
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, double total, int count) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Card(
        color: cs.primaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Sales',
                      style: AppTypography.bodyMedium(context).copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '₱${total.toStringAsFixed(2)}',
                      style: AppTypography.titleLargeBold(context).copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Transactions',
                      style: AppTypography.bodyMedium(context).copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '$count',
                      style: AppTypography.titleLargeBold(context).copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

    final chips = <Widget>[
      _buildPill(sale.paymentMethod, cs),
      if (sale.customerName != null && sale.customerName!.isNotEmpty)
        _buildPill(sale.customerName!, cs),
      if (sale.referenceNumber != null && sale.referenceNumber!.isNotEmpty)
        _buildPill('Ref: ${sale.referenceNumber}', cs),
    ];

    final actions = <AppListAction>[
      if (canVoid && sale.paymentStatus == 'confirmed')
        AppListAction(
          icon: Icons.delete,
          tooltip: 'Void sale',
          color: cs.error,
          onPressed: () => _voidSale(sale),
        ),
    ];

    return AppListItem(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      title: 'Sale #${sale.receiptNumber ?? sale.id}',
      subtitle: time,
      trailing: Text(
        '₱${sale.totalAmount.toStringAsFixed(2)}',
        style: AppTypography.titleMediumBold(context)
            .copyWith(color: cs.primary),
      ),
      chips: chips,
      statusLabel: _statusLabel(sale.paymentStatus),
      statusColor: statusColor,
      statusIcon: _statusIcon(sale.paymentStatus),
      actions: actions.isNotEmpty ? actions : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SaleDetailScreen(sale: sale),
          ),
        );
      },
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
        style: AppTypography.labelMedium(context).copyWith(
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
