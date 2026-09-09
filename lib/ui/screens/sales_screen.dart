import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/report_export_service.dart';
import 'package:pinoy_pos/services/sales_import_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/summary_stat_card.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

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

  /// Quick-filter payment methods shown as chips below the search bar.
  static const _paymentMethods = ['Cash', 'GCash', 'Card', 'Other'];

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

    try {
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load sales: $e';
          _isLoading = false;
        });
      }
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
            // Voiding a sale restores product stock.
            bumpCatalogRevision(ref);
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

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    _loadSales();
  }

  Future<void> _showFilterDialog() async {
    const statuses = ['pending', 'confirmed', 'cancelled', 'refunded'];

    final result = await showDialog<_SalesFilter?>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AppDialogForm<_SalesFilter?>(
        type: AppDialogType.info,
        title: 'Filter Sales',
        childBuilder: (context, state) {
          final selectedMethod =
              state.value<String?>('method', _selectedPaymentMethod);
          final selectedStatus =
              state.value<String?>('status', _selectedPaymentStatus);

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDropdownField<String?>(
                  key: const ValueKey('filter_payment_method'),
                  label: 'Payment Method',
                  prefixIcon: Icons.payments_outlined,
                  initialValue: selectedMethod,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All'),
                    ),
                    ..._paymentMethods.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m,
                        child: Text(m),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      state.setValue<String?>('method', value),
                ),
                const SizedBox(height: 16),
                AppDropdownField<String?>(
                  key: const ValueKey('filter_payment_status'),
                  label: 'Status',
                  prefixIcon: Icons.check_circle_outlined,
                  initialValue: selectedStatus,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All active'),
                    ),
                    ...statuses.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s,
                        child: Text(s[0].toUpperCase() + s.substring(1)),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      state.setValue<String?>('status', value),
                ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) => state.pop(null),
          ),
          AppDialogAction(
            label: 'Apply',
            isPrimary: true,
            onPressed: (context) => state.pop(
              _SalesFilter(
                state.value<String?>('method'),
                state.value<String?>('status'),
              ),
            ),
          ),
        ],
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

  // ── Sales export ──────────────────────────────────────────────────────
  //
  // Direct export of the sales slice currently shown on this screen. This
  // is a data-management action — it reuses the established report export
  // pipeline (PDF/Excel/CSV) and never enters the staff "submit report"
  // workflow.

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Export Sales',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.md),
              _ExportTile(
                icon: Icons.picture_as_pdf,
                label: 'PDF',
                onTap: () => _exportSales(ExportFormat.pdf),
              ),
              _ExportTile(
                icon: Icons.table_chart,
                label: 'Excel',
                onTap: () => _exportSales(ExportFormat.excel),
              ),
              _ExportTile(
                icon: Icons.description,
                label: 'CSV',
                onTap: () => _exportSales(ExportFormat.csv),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportSales(ExportFormat format) async {
    Navigator.pop(context);
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final bounds = _periodBounds();
      final analytics = await ref
          .read(salesAnalyticsServiceProvider)
          .getAnalyticsForBounds(
            bounds,
            paymentMethod: _selectedPaymentMethod,
            paymentStatus: _selectedPaymentStatus ?? 'confirmed',
          );
      final store = await ref.read(reportServiceProvider).getStoreInfo();
      final savedPath = await ReportExportService().exportSalesReport(
        analytics: analytics,
        store: store,
        format: format,
      );

      if (!mounted) return;
      if (savedPath != null && savedPath.isNotEmpty) {
        await AppDialogService.success(
          context,
          title: 'Export Complete',
          message: 'The sales file was saved to:',
          details: savedPath,
          primaryLabel: 'Done',
        );
      } else {
        await AppDialogService.warning(
          context,
          title: 'Export Cancelled',
          message: 'No file was saved.',
        );
      }
    } catch (e) {
      if (mounted) {
        await AppDialogService.error(
          context,
          title: 'Export Failed',
          message: 'The sales records could not be exported.',
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Sales import ──────────────────────────────────────────────────────
  //
  // Owner-only CSV import: pick file -> validate -> preview -> confirm ->
  // save. This never creates report records; it writes sale rows through
  // SalesImportService and records an activity-log entry.

  Future<void> _importSales() async {
    if (_isProcessing) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      await AppDialogService.warning(
        context,
        title: 'No file data',
        message: 'The selected file could not be read.',
      );
      return;
    }

    final importService = ref.read(salesImportServiceProvider);
    final SalesImportPreview? preview;
    try {
      preview = await importService.previewSalesImport(
        fileName: file.name,
        bytes: bytes,
      );
    } on AuthorizationException {
      if (mounted) {
        await AppDialogService.accessDenied(context);
      }
      return;
    }
    if (!mounted) return;

    if (preview == null) {
      await AppDialogService.warning(
        context,
        title: 'Not supported',
        message: 'Sales import is not available on the web.',
      );
      return;
    }

    if (preview.fileError != null) {
      await AppDialogService.error(
        context,
        title: 'Invalid File',
        message: preview.fileError!,
        details: 'Expected columns: date, total, payment_method, '
            'payment_status, cash_received, customer, reference, '
            'receipt_number, notes.',
      );
      return;
    }

    if (preview.validRows.isEmpty) {
      await AppDialogService.warning(
        context,
        title: 'Nothing to import',
        message: 'Every row in ${preview.fileName} failed validation.',
      );
      return;
    }

    final confirmed = await _showImportPreview(preview);
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final importResult = await importService.importSales(preview);
      if (!mounted) return;

      final failed = importResult.errors.length;
      await AppDialogService.success(
        context,
        title: 'Import Complete',
        message:
            'Imported ${importResult.imported} sale record(s) from ${preview.fileName}.',
        details: [
          if (importResult.skipped > 0)
            '${importResult.skipped} duplicate receipt number(s) skipped',
          if (preview.invalidRows.isNotEmpty)
            '${preview.invalidRows.length} row(s) failed validation',
          if (failed > 0) '$failed row(s) failed to save',
        ].join('\n'),
        primaryLabel: 'Done',
      );
      _loadSales();
    } on AuthorizationException {
      if (mounted) {
        await AppDialogService.accessDenied(context);
      }
    } catch (e) {
      if (mounted) {
        await AppDialogService.error(
          context,
          title: 'Import Failed',
          message: 'The sales records could not be imported.',
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _showImportPreview(SalesImportPreview preview) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialog(
        type: AppDialogType.confirmation,
        title: 'Import Sales',
        message: '${preview.fileName}: ${preview.validRows.length} valid '
            'row(s), ${preview.invalidRows.length} invalid.',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(false),
          ),
          AppDialogAction(
            label: 'Import ${preview.validRows.length} record(s)',
            isPrimary: true,
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: preview.rows.length > 50 ? 50 : preview.rows.length,
            itemBuilder: (context, index) =>
                _ImportPreviewRow(row: preview.rows[index]),
          ),
        ),
      ),
    );
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
        body: ErrorState(title: 'Error', message: _error, onRetry: _loadSales),
      );
    }

    final filtersActive =
        _selectedPaymentMethod != null ||
        _selectedPaymentStatus != null ||
        _searchQuery.isNotEmpty ||
        _selectedPeriod != ReportingPeriod.thisMonth;

    final grouped = _groupByDate(_sales);
    final totalAmount = _sales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final pendingCount = _sales.where((s) => s.paymentStatus == 'pending').length;

    return Scaffold(
      appBar: const AppHeader(title: 'My Sales'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: RefreshIndicator(
            onRefresh: _loadSales,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildPeriodHeader(context, totalAmount, pendingCount),
                ),
                if (_sales.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
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
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final group = grouped[index];
                        final groupTotal = group.sales.fold<double>(
                          0,
                          (sum, sale) => sum + sale.totalAmount,
                        );
                        return AppSection(
                          title: group.label,
                          subtitle:
                              '${group.sales.length} sale${group.sales.length == 1 ? '' : 's'} · ${CurrencyUtils.format(groupTotal)}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: group.sales
                                .map(
                                  (sale) =>
                                      _buildSaleCard(sale, canVoid, context),
                                )
                                .toList(),
                          ),
                        );
                      }, childCount: grouped.length),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodHeader(
    BuildContext context,
    double totalAmount,
    int pendingCount,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PeriodSelector(
            selected: _selectedPeriod,
            onSelected: _onPeriodSelected,
            customStart: _customStart,
            customEnd: _customEnd,
            onCustomRange: _onCustomRange,
          ),
          const SizedBox(height: Spacing.sm),
          _buildStatsStrip(context, totalAmount, pendingCount),
          const SizedBox(height: Spacing.sm),
          _buildSearchBar(context),
          const SizedBox(height: Spacing.sm),
          _buildMethodChips(context),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(BuildContext context, double total, int pending) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final warningColor =
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    final purpleColor =
        AppSemanticColors.resolve(AppSemanticColors.purple, brightness);

    return Row(
      children: [
        Expanded(
          child: SummaryStatCard(
            icon: Icons.receipt_long_outlined,
            color: cs.primary,
            value: CurrencyUtils.format(total),
            label: 'Total Sales',
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: SummaryStatCard(
            icon: Icons.shopping_cart_outlined,
            color: purpleColor,
            value: '${_sales.length}',
            label: 'Transactions',
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: SummaryStatCard(
            icon: Icons.warning_amber,
            color: warningColor,
            value: '$pending',
            label: 'Pending',
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppSearchField(
            controller: _searchController,
            hint: 'Search receipt, customer, or reference...',
            onChanged: (value) => setState(() => _searchQuery = value),
            onSubmitted: (_) => _loadSales(),
            onClear: _clearSearch,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        AppIconButton(
          icon: Icons.filter_list,
          tooltip: 'Filters',
          onPressed: _isProcessing ? null : _showFilterDialog,
        ),
        if (ref
            .read(authStateProvider.notifier)
            .hasPermission('export_reports')) ...[
          const SizedBox(width: Spacing.xs),
          AppIconButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Export sales',
            onPressed: _isProcessing ? null : _showExportSheet,
          ),
        ],
        if (ref
            .read(authStateProvider.notifier)
            .hasPermission('import_sales')) ...[
          const SizedBox(width: Spacing.xs),
          AppIconButton(
            icon: Icons.file_upload_outlined,
            tooltip: 'Import sales',
            onPressed: _isProcessing ? null : _importSales,
          ),
        ],
        const SizedBox(width: Spacing.xs),
        AppIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: _isProcessing ? null : _loadSales,
        ),
      ],
    );
  }

  Widget _buildMethodChips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[
      _MethodChip(
        label: 'All',
        selected: _selectedPaymentMethod == null,
        onSelected: (_) => _onMethodSelected(null),
      ),
      for (final method in _paymentMethods)
        _MethodChip(
          label: method,
          selected: _selectedPaymentMethod == method,
          onSelected: (_) => _onMethodSelected(method),
        ),
      if (_selectedPaymentMethod != null ||
          _selectedPaymentStatus != null ||
          _searchQuery.isNotEmpty)
        TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear, size: 18),
          label: const Text('Clear'),
          style: TextButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
    ];

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: chips,
    );
  }

  void _onMethodSelected(String? method) {
    if (method == _selectedPaymentMethod) return;
    setState(() => _selectedPaymentMethod = method);
    _loadSales();
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
      // Sunday is the first day of the week.
      const dayNames = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      return dayNames[local.weekday % 7];
    }
    return '${local.month}/${local.day}/${local.year}';
  }

  Widget _buildSaleCard(Sale sale, bool canVoid, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(sale.paymentStatus, cs);
    final statusIcon = _statusIcon(sale.paymentStatus);
    final time = _formatTime(sale.createdAt);

    final customerText = (sale.customerName != null &&
            sale.customerName!.trim().isNotEmpty)
        ? ' · ${sale.customerName}'
        : '';

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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: 'Sale #${sale.receiptNumber ?? sale.id}',
      subtitle: '$time · ${sale.paymentMethod}$customerText',
      trailing: Text(
        CurrencyUtils.format(sale.totalAmount),
        style: AppTypography.titleMediumBold(
          context,
        ).copyWith(color: cs.primary),
      ),
      statusLabel: _statusLabel(sale.paymentStatus),
      statusColor: statusColor,
      statusIcon: statusIcon,
      actions: actions.isNotEmpty ? actions : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SaleDetailScreen(sale: sale)),
        );
      },
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
    final brightness = Theme.of(context).brightness;
    return switch (status) {
      'confirmed' =>
        AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      'pending' =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
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

/// Compact choice chip for the payment-method quick filter. Uses the
/// application's chip radius and surface colors so it adapts to both themes.
class _MethodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool?> onSelected;

  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected ? cs.onPrimary : cs.onSurface;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: cs.primary,
      backgroundColor: cs.surface,
      side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    );
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

/// A format option in the export bottom sheet.
class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExportTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One row in the import preview dialog. Invalid rows are shown in the
/// error colour with their validation message instead of the parsed data.
class _ImportPreviewRow extends StatelessWidget {
  final SalesImportRow row;

  const _ImportPreviewRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!row.isValid) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Line ${row.lineNumber}: ${row.error}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.error),
        ),
      );
    }

    final date = row.date == null
        ? ''
        : '${row.date!.year}-${row.date!.month.toString().padLeft(2, '0')}-'
            '${row.date!.day.toString().padLeft(2, '0')}';
    final summary = 'Line ${row.lineNumber}: $date · ${row.paymentMethod} · '
        '${CurrencyUtils.format(row.totalAmount ?? 0)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        summary,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
