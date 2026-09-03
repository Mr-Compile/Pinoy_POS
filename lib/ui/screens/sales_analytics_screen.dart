import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/sales_analytics_provider.dart';
import 'package:pinoy_pos/providers/staff_provider.dart';
import 'package:pinoy_pos/services/report_export_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/category_sales_bar_chart.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_view.dart';
import 'package:pinoy_pos/ui/widgets/peak_sales_card.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';
import 'package:pinoy_pos/ui/widgets/sales_line_chart.dart';
import 'package:pinoy_pos/ui/widgets/sales_summary_cards.dart';
import 'package:pinoy_pos/ui/widgets/sales_transactions_list.dart';
import 'package:pinoy_pos/ui/widgets/staff_performance_list.dart';
import 'package:pinoy_pos/ui/widgets/top_products_bar_chart.dart';

/// Sales Analytics screen (the new Reports / Sales Analytics hub).
class SalesAnalyticsScreen extends ConsumerStatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  ConsumerState<SalesAnalyticsScreen> createState() =>
      _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends ConsumerState<SalesAnalyticsScreen> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesAnalyticsProvider);
    final staffState = ref.watch(staffControllerProvider);
    final canExport =
        ref.read(authStateProvider.notifier).hasPermission('export_reports');
    final canViewStaff =
        ref.read(authStateProvider.notifier).hasPermission('view_staff_performance');

    return Scaffold(
      appBar: const AppHeader(title: 'Reports'),
      body: state.isLoading && state.analytics == null
          ? const LoadingState(message: 'Loading sales analytics...')
          : _buildBody(
              context,
              state,
              canExport,
              staffState.staff,
              staffState.isLoading,
              canViewStaff,
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SalesAnalyticsState state,
    bool canExport,
    List<User> staff,
    bool staffLoading,
    bool canViewStaff,
  ) {
    if (state.error != null) {
      return ErrorState(
        title: 'Something went wrong',
        message: state.error!,
        onRetry: () => ref.read(salesAnalyticsProvider.notifier).load(),
      );
    }

    final analytics = state.analytics;
    if (analytics == null) {
      return const ErrorState(
        title: 'No analytics data',
        message: 'Analytics could not be loaded.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.read(salesAnalyticsProvider.notifier).load(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.md),
            PeriodSelector(
              selected: state.period,
              onSelected: (p) =>
                  ref.read(salesAnalyticsProvider.notifier).selectPeriod(p),
              customStart: state.customStart,
              customEnd: state.customEnd,
              onCustomRange: (range) => ref
                  .read(salesAnalyticsProvider.notifier)
                  .setCustomRange(range.start, range.end),
            ),
            const SizedBox(height: Spacing.sm),
            ResponsiveBuilder(
              builder: (context, layout) {
                if (layout.isCompact) {
                  return _buildCompactActionsBar(
                    context,
                    state,
                    canExport,
                    canViewStaff,
                  );
                }
                if (staff.isEmpty && !staffLoading) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ref.read(staffControllerProvider.notifier).loadStaff();
                    }
                  });
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: _buildFilterBar(
                    context,
                    state,
                    staff,
                    canViewStaff,
                    isCompact: false,
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildPeriodHeader(context, state),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: SalesSummaryCards(
                analytics: analytics,
                storeInfo: state.storeInfo,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Sales Trend',
                subtitle: _trendSubtitle(analytics.bounds),
                child: SalesLineChart(
                  points: analytics.trend,
                  groupBy: analytics.bounds.groupBy,
                  valuePrefix: CurrencyUtils.symbol(currency: state.storeInfo?.currency),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Sales vs Previous Period',
                subtitle: _trendSubtitle(analytics.bounds),
                child: SalesComparisonChart(
                  current: analytics.trend,
                  previous: analytics.previousTrend,
                  groupBy: analytics.bounds.groupBy,
                  valuePrefix: CurrencyUtils.symbol(currency: state.storeInfo?.currency),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _ResponsiveTwoColumn(
                left: AppSection(
                  title: 'Payment Methods',
                  child: PaymentBreakdownView(
                    breakdown: analytics.paymentBreakdown,
                    grandTotal: analytics.totalSales,
                    storeInfo: state.storeInfo,
                  ),
                ),
                right: AppSection(
                  title: 'Top Products',
                  child: TopProductsBarChart(
                    products: analytics.topProducts,
                    storeInfo: state.storeInfo,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Sales by Category',
                child: CategorySalesBarChart(
                  categorySales: analytics.categorySales,
                  storeInfo: state.storeInfo,
                ),
              ),
            ),
            if (analytics.staffSummaries.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: AppSection(
                  title: 'Staff Performance',
                  child: StaffPerformanceList(
                    staff: analytics.staffSummaries,
                    storeInfo: state.storeInfo,
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Peak Sales Period',
                child: PeakSalesCard(peak: analytics.peakSalesPeriod),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Recent Transactions',
                subtitle: 'Confirmed sales for the selected period',
                child: SalesTransactionsList(
                  sales: analytics.sales,
                  storeInfo: state.storeInfo,
                  staffNames: {
                    for (final s in analytics.staffSummaries) s.userId: s.fullName,
                  },
                  onTap: _openSale,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  void _showFilterBottomSheet(
    SalesAnalyticsState state,
    List<User> staff,
    bool canViewStaff,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Consumer(
              builder: (context, ref, _) {
                final analyticsState = ref.watch(salesAnalyticsProvider);
                final staffState = ref.watch(staffControllerProvider);
                if (staffState.staff.isEmpty && !staffState.isLoading) {
                  Future.microtask(() {
                    ref.read(staffControllerProvider.notifier).loadStaff();
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: Spacing.md),
                    _buildFilterBar(
                      context,
                      analyticsState,
                      staffState.staff,
                      canViewStaff,
                      isCompact: true,
                      currentMethod: analyticsState.paymentMethod,
                      currentStatus: analyticsState.paymentStatus,
                      currentStaff: analyticsState.selectedStaffId,
                      onMethodChanged: (v) => ref
                          .read(salesAnalyticsProvider.notifier)
                          .setPaymentMethod(v),
                      onStatusChanged: (v) => ref
                          .read(salesAnalyticsProvider.notifier)
                          .setPaymentStatus(v),
                      onStaffChanged: (v) => ref
                          .read(salesAnalyticsProvider.notifier)
                          .setStaff(v),
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            ref
                                .read(salesAnalyticsProvider.notifier)
                                .clearFilters();
                            Navigator.pop(context);
                          },
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    SalesAnalyticsState state,
    List<User> staff,
    bool canViewStaff, {
    required bool isCompact,
    String? currentMethod,
    String? currentStatus,
    int? currentStaff,
    ValueChanged<String?>? onMethodChanged,
    ValueChanged<String?>? onStatusChanged,
    ValueChanged<int?>? onStaffChanged,
  }) {
    final children = <Widget>[
      if (canViewStaff) _buildStaffDropdown(currentStaff, staff, onStaffChanged),
      _buildPaymentMethodDropdown(currentMethod, onMethodChanged),
      _buildPaymentStatusDropdown(currentStatus, onStatusChanged),
    ];

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: c,
                ))
            .toList(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: Spacing.md),
                  child: c,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildCompactActionsBar(
    BuildContext context,
    SalesAnalyticsState state,
    bool canExport,
    bool canViewStaff,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _showFilterBottomSheet(state, [], canViewStaff),
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Filters'),
          ),
          const Spacer(),
          if (canExport)
            FilledButton.icon(
              onPressed: state.analytics == null ? null : _showExportMenu,
              icon: const Icon(Icons.download),
              label: const Text('Export'),
            ),
        ],
      ),
    );
  }

  Widget _buildStaffDropdown(
    int? value,
    List<User> staff,
    ValueChanged<int?>? onChanged,
  ) {
    final items = [
      const DropdownMenuItem<int>(value: null, child: Text('All staff')),
      ...staff
          .where((u) => u.id != null)
          .map((u) => DropdownMenuItem<int>(value: u.id, child: Text(u.fullName))),
    ];
    return _buildDropdown<int>(
      value: value,
      label: 'Staff',
      hint: 'All staff',
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildPaymentMethodDropdown(
    String? value,
    ValueChanged<String?>? onChanged,
  ) {
    const methods = ['Cash', 'GCash', 'Card', 'Other'];
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('All methods')),
      ...methods.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))),
    ];
    return _buildDropdown<String>(
      value: value,
      label: 'Payment method',
      hint: 'All methods',
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildPaymentStatusDropdown(
    String? value,
    ValueChanged<String?>? onChanged,
  ) {
    const statuses = ['pending', 'confirmed', 'failed', 'cancelled', 'refunded'];
    final labels = {
      'pending': 'Pending',
      'confirmed': 'Confirmed',
      'failed': 'Failed',
      'cancelled': 'Cancelled',
      'refunded': 'Refunded',
    };
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('All active')),
      ...statuses.map(
        (s) => DropdownMenuItem<String>(value: s, child: Text(labels[s]!)),
      ),
    ];
    return _buildDropdown<String>(
      value: value,
      label: 'Payment status',
      hint: 'All active',
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String label,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPeriodHeader(BuildContext context, SalesAnalyticsState state) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.periodLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                state.analytics == null
                    ? ''
                    : '${_formatDate(state.analytics!.bounds.start)} - ${_formatDate(state.analytics!.bounds.end.subtract(const Duration(days: 1)))}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (state.storeInfo == null)
          TextButton.icon(
            onPressed: _openStoreSettings,
            icon: const Icon(Icons.storefront),
            label: const Text('Set store'),
          ),
      ],
    );
  }

  String _trendSubtitle(ReportingPeriodBounds bounds) {
    return switch (bounds.groupBy) {
      ReportGroupBy.hour => 'By hour',
      ReportGroupBy.day => 'By day',
      ReportGroupBy.week => 'By week',
      ReportGroupBy.month => 'By month',
    };
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  void _openSale(Sale sale) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(saleId: sale.id!),
      ),
    );
  }

  void _openStoreSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StoreInformationSettingsPage(),
      ),
    );
  }

  void _showExportMenu() {
    final analytics = ref.read(salesAnalyticsProvider).analytics;
    if (analytics == null) return;

    final isStaff =
        ref.read(authStateProvider.notifier).currentUser?.role == UserRole.staff;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isStaff ? 'Report' : 'Export Report',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.md),
              _ExportFormatTile(
                icon: Icons.picture_as_pdf,
                label: 'PDF',
                onTap: () => _export(ExportFormat.pdf),
              ),
              _ExportFormatTile(
                icon: Icons.table_chart,
                label: 'Excel',
                onTap: () => _export(ExportFormat.excel),
              ),
              _ExportFormatTile(
                icon: Icons.description,
                label: 'CSV',
                onTap: () => _export(ExportFormat.csv),
              ),
              if (isStaff) ...[
                const Divider(),
                _ExportFormatTile(
                  icon: Icons.send,
                  label: 'Submit to Owner',
                  onTap: _submit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    Navigator.pop(context);
    if (_isExporting) return;

    final analytics = ref.read(salesAnalyticsProvider).analytics;
    final store = ref.read(salesAnalyticsProvider).storeInfo;
    if (analytics == null || store == null) return;

    setState(() => _isExporting = true);
    try {
      final savedPath = await ReportExportService().submitSalesReport(
        analytics: analytics,
        store: store,
        format: ExportFormat.pdf,
      );

      if (mounted) {
        if (savedPath != null && savedPath.isNotEmpty) {
          await AppDialogService.success(
            context,
            title: 'Report Submitted',
            message: 'The report has been submitted to the Owner.',
            details: savedPath,
            primaryLabel: 'Done',
          );
        } else {
          await AppDialogService.warning(
            context,
            title: 'Submission Cancelled',
            message: 'No file was saved.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        await AppDialogService.error(
          context,
          title: 'Submission Failed',
          message: 'The report could not be submitted.',
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _export(ExportFormat format) async {
    Navigator.pop(context);
    if (_isExporting) return;

    final analytics = ref.read(salesAnalyticsProvider).analytics;
    final store = ref.read(salesAnalyticsProvider).storeInfo;
    if (analytics == null || store == null) return;

    setState(() => _isExporting = true);
    try {
      final savedPath = await ReportExportService().exportSalesReport(
        analytics: analytics,
        store: store,
        format: format,
      );
      if (mounted) {
        if (savedPath != null && savedPath.isNotEmpty) {
          await AppDialogService.success(
            context,
            title: 'Report Exported',
            message: 'The report was saved to:',
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
      }
    } catch (e) {
      if (mounted) {
        await AppDialogService.error(
          context,
          title: 'Export Failed',
          message: 'The report could not be exported.',
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}

class _ExportFormatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExportFormatTile({
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

class _ResponsiveTwoColumn extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsiveTwoColumn({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: Spacing.md),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [left, const SizedBox(height: Spacing.lg), right],
        );
      },
    );
  }
}
