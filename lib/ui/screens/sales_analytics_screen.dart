import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/sales_analytics_provider.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/services/report_export_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/category_sales_bar_chart.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_view.dart';
import 'package:pinoy_pos/ui/widgets/sales_period_selector.dart';
import 'package:pinoy_pos/ui/widgets/sales_summary_cards.dart';
import 'package:pinoy_pos/ui/widgets/sales_trend_chart.dart';
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
    final canExport =
        ref.read(authStateProvider.notifier).hasPermission('export_reports');

    return Scaffold(
      appBar: const AppHeader(
        title: 'Reports',
      ),
      body: state.isLoading && state.analytics == null
          ? const LoadingState(message: 'Loading sales analytics...')
          : _buildBody(context, state, canExport),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SalesAnalyticsState state,
    bool canExport,
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

    final filter = ref.watch(salesPeriodFilterProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.read(salesAnalyticsProvider.notifier).load(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: SalesSummaryCards(
                analytics: analytics,
                storeInfo: state.storeInfo,
              ),
            ),
            const SizedBox(height: Spacing.md),
            const SalesPeriodSelector(),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildPeriodHeader(context, state, filter),
            ),
            const SizedBox(height: Spacing.sm),
            ResponsiveBuilder(
              builder: (context, layout) {
                if (layout.isCompact) {
                  return _buildCompactActionsBar(
                    context,
                    state,
                    canExport,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: _buildFilterBar(
                    context,
                    state,
                    isCompact: false,
                    canExport: canExport,
                  ),
                );
              },
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Sales Trend',
                child: SalesTrendChart(
                  trend: analytics.trend,
                  groupBy: analytics.bounds.groupBy,
                  period: filter.period,
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

  void _showFilterBottomSheet(SalesAnalyticsState state) {
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
                          borderRadius: BorderRadius.circular(AppRadius.xs),
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
                      isCompact: true,
                      canExport: false,
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
                          child: const Text('Apply'),
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
    SalesAnalyticsState state, {
    required bool isCompact,
    required bool canExport,
  }) {
    final dropdowns = <Widget>[
      _buildPaymentMethodDropdown(
        state.paymentMethod,
        (v) => ref.read(salesAnalyticsProvider.notifier).setPaymentMethod(v),
      ),
      _buildPaymentStatusDropdown(
        state.paymentStatus,
        (v) => ref.read(salesAnalyticsProvider.notifier).setPaymentStatus(v),
      ),
    ];

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: dropdowns
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: c,
                ))
            .toList(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...dropdowns.map((c) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: Spacing.md),
                child: c,
              ),
            )),
        if (canExport)
          FilledButton.icon(
            onPressed: state.analytics == null ? null : _showExportMenu,
            icon: const Icon(Icons.download),
            label: const Text('Export'),
          ),
      ],
    );
  }

  Widget _buildCompactActionsBar(
    BuildContext context,
    SalesAnalyticsState state,
    bool canExport,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _showFilterBottomSheet(state),
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

  Widget _buildPaymentMethodDropdown(
    String? value,
    ValueChanged<String?>? onChanged,
  ) {
    const methods = ['Cash', 'GCash'];
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
    return AppDropdown<T>(
      value: value,
      label: label,
      hint: hint,
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildPeriodHeader(
    BuildContext context,
    SalesAnalyticsState state,
    SalesPeriodFilter filter,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatSalesPeriodLabel(filter),
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

    // "Submit to Owner" is the Staff report workflow. It is gated on the
    // Staff-only `submit_reports` permission (enforced again in
    // ReportExportService.submitSalesReport) so the Owner is never offered
    // a staff-style submission path.
    final canSubmit = ref
        .read(authStateProvider.notifier)
        .hasPermission('submit_reports');

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                canSubmit ? 'Report' : 'Export Report',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.md),
              _ExportFormatTile(
                icon: Icons.picture_as_pdf,
                label: 'PDF',
                subtitle: 'Print-friendly sales summary',
                iconColor: AppSemanticColors.resolve(
                  AppSemanticColors.error,
                  Theme.of(context).brightness,
                ),
                onTap: () => _export(ExportFormat.pdf),
              ),
              _ExportFormatTile(
                icon: Icons.table_chart,
                label: 'Excel',
                subtitle: 'Spreadsheet with summary and transactions',
                iconColor: AppSemanticColors.resolve(
                  AppSemanticColors.success,
                  Theme.of(context).brightness,
                ),
                onTap: () => _export(ExportFormat.excel),
              ),
              if (canSubmit)
                _ExportFormatTile(
                  icon: Icons.send,
                  label: 'Submit to Owner',
                  subtitle: 'Staff workflow: generate PDF and send',
                  iconColor: AppSemanticColors.resolve(
                    AppSemanticColors.primary,
                    Theme.of(context).brightness,
                  ),
                  onTap: _submit,
                ),
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
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ExportFormatTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? cs.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: effectiveIconColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: effectiveIconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodyMediumSemibold(context).copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
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
        if (layoutClassFor(constraints.maxWidth).isAtLeastMedium) {
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
