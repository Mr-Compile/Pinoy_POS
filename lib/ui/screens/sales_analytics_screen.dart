import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/sales_analytics_provider.dart';
import 'package:pinoy_pos/services/report_export_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_list.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';
import 'package:pinoy_pos/ui/widgets/product_performance_list.dart';
import 'package:pinoy_pos/ui/widgets/sales_summary_cards.dart';
import 'package:pinoy_pos/ui/widgets/sales_transactions_list.dart';
import 'package:pinoy_pos/ui/widgets/sales_trend_chart.dart';
import 'package:pinoy_pos/ui/widgets/staff_performance_list.dart';

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
      appBar: AppHeader(
        title: 'Reports',
        actions: [
          if (canExport)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export report',
              onPressed: state.analytics == null ? null : _showExportMenu,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(salesAnalyticsProvider.notifier).load(),
          ),
        ],
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
                child: SalesTrendChart(
                  trend: analytics.trend,
                  groupBy: analytics.bounds.groupBy,
                  valuePrefix: state.storeInfo?.currency,
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _ResponsiveTwoColumn(
                left: AppSection(
                  title: 'Payment Methods',
                  child: PaymentBreakdownList(
                    breakdown: analytics.paymentBreakdown,
                    grandTotal: analytics.totalSales,
                    storeInfo: state.storeInfo,
                  ),
                ),
                right: AppSection(
                  title: 'Top Products',
                  child: ProductPerformanceList(
                    products: analytics.topProducts,
                    storeInfo: state.storeInfo,
                  ),
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

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Export Report',
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export(ExportFormat format) async {
    Navigator.pop(context);
    if (_isExporting) return;

    final analytics = ref.read(salesAnalyticsProvider).analytics;
    final store = ref.read(salesAnalyticsProvider).storeInfo;
    if (analytics == null || store == null) return;

    setState(() => _isExporting = true);
    try {
      final ok = await ReportExportService().exportSalesReport(
        analytics: analytics,
        store: store,
        format: format,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Report exported successfully.'
                : 'Export cancelled or failed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
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
