import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/peak_sales_period.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/dashboard_provider.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_config_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_analytics_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/staff_management_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/category_sales_bar_chart.dart';
import 'package:pinoy_pos/ui/widgets/donut_chart.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/kpi_card.dart';
import 'package:pinoy_pos/ui/widgets/peak_sales_card.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_view.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';
import 'package:pinoy_pos/ui/widgets/sales_line_chart.dart';
import 'package:pinoy_pos/ui/widgets/sales_summary_cards.dart';
import 'package:pinoy_pos/ui/widgets/staff_performance_list.dart';
import 'package:pinoy_pos/ui/widgets/top_products_bar_chart.dart';

/// Role-based dashboard screen.
///
/// Architecture:
///   UI → DashboardProvider → DashboardService → Repository → DAO → SQLite
///
/// The screen never queries SQLite, never computes analytics, and never
/// instantiates services directly. It watches [dashboardProvider] and
/// renders the role-appropriate layout. All numbers come from real
/// SQLite data fetched through the service layer.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final dashboardState = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: const AppHeader(title: 'Dashboard'),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).load(),
        child: switch (dashboardState) {
          DashboardLoading() => _DashboardLoadingView(user: user),
          DashboardDenied() => const _DashboardDeniedView(),
          DashboardError(:final message) => ErrorState(
              title: 'Unable to Load Dashboard',
              message: message,
              onRetry: () => ref.read(dashboardProvider.notifier).load(),
            ),
          DashboardLoaded(:final data) => _DashboardLoadedView(
              user: user,
              data: data,
            ),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Loaded view — dispatches to the role-specific dashboard.
// ─────────────────────────────────────────────────────────────────────────

class _DashboardLoadedView extends ConsumerWidget {
  final User? user;
  final DashboardData data;

  const _DashboardLoadedView({
    this.user,
    required this.data,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return const Center(child: Text('Not authenticated'));
    }

    final state = ref.watch(dashboardProvider);
    // The Admin dashboard is system/maintenance only — none of its metrics
    // are period-driven, so the selector is hidden for that role.
    final showPeriodSelector = data is! AdminDashboardData;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeHeader(user: user!),
          if (showPeriodSelector) ...[
            const SizedBox(height: Spacing.md),
            PeriodSelector(
              selected: state.period,
              customStart: state.customStart,
              customEnd: state.customEnd,
              onSelected: (period) {
                ref.read(dashboardProvider.notifier).selectPeriod(period);
              },
              onCustomRange: (range) {
                ref
                    .read(dashboardProvider.notifier)
                    .setCustomRange(range.start, range.end);
              },
            ),
          ],
          const SizedBox(height: Spacing.xl),
          // Dispatch on the loaded payload's type — guaranteed to match the
          // role the service scoped the data for, even if the session user
          // changed while the load was in flight.
          switch (data) {
            OwnerDashboardData d => _OwnerDashboard(data: d),
            AdminDashboardData d => _AdminDashboard(data: d),
            StaffDashboardData d => _StaffDashboard(data: d),
          },
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Denied view — authenticated user without `view_dashboard` permission
// ─────────────────────────────────────────────────────────────────────────

class _DashboardDeniedView extends StatelessWidget {
  const _DashboardDeniedView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: cs.error),
            const SizedBox(height: Spacing.lg),
            Text(
              'Access Denied',
              style: AppTypography.headlineSmallBold(context),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'You do not have permission to view the dashboard.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Loading skeleton view
// ─────────────────────────────────────────────────────────────────────────

class _DashboardLoadingView extends StatelessWidget {
  final User? user;

  const _DashboardLoadingView({this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user != null) _WelcomeHeader(user: user!),
          const SizedBox(height: Spacing.xl),
          // Skeleton KPI grid
          KpiGrid(
            children: List.generate(
              4,
              (_) => const KpiCardSkeleton(tier: KpiCardTier.secondary),
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          // Skeleton chart card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 20,
                  width: 160,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  final User user;
  const _WelcomeHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, ${user.fullName}',
                style: AppTypography.headlineSmallBold(context),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.badge_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      user.role.displayName,
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}



/// Formats a DateTime for compact recent-activity display.
String _formatDateTime(DateTime dt) {
  return DateFormat('MMM d \u00b7 h:mm a').format(dt.toLocal());
}

// ─────────────────────────────────────────────────────────────────────────
// Owner Dashboard
// ─────────────────────────────────────────────────────────────────────────

class _OwnerDashboard extends ConsumerWidget {
  final OwnerDashboardData data;
  const _OwnerDashboard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = data.analytics;
    final currencySymbol = CurrencyUtils.symbol();
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary KPIs ──
        AppSection(
          title: 'Key Performance Indicators',
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: SalesSummaryCards(
            analytics: analytics,
            storeInfo: null,
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Quick actions ──
        _buildOwnerQuickActions(context, ref, authNotifier),
        const SizedBox(height: Spacing.xxl),

        // ── Sales trend ──
        _buildSalesTrendCard(context, analytics, currencySymbol),
        const SizedBox(height: Spacing.xxl),

        // ── Period comparison ──
        _buildComparisonChart(context, analytics, currencySymbol),
        const SizedBox(height: Spacing.xxl),

        // ── Two-column: payment breakdown + top products ──
        _buildPaymentAndTopProducts(context, analytics),
        const SizedBox(height: Spacing.xxl),

        // ── Category sales ──
        _buildCategorySalesCard(context, analytics),
        const SizedBox(height: Spacing.xxl),

        // ── Staff performance ──
        if (analytics.staffSummaries.isNotEmpty) ...[
          _buildStaffPerformanceSection(context, analytics.staffSummaries),
          const SizedBox(height: Spacing.xxl),
        ],

        // ── Peak sales ──
        _buildPeakSalesCard(context, analytics.peakSalesPeriod),
        const SizedBox(height: Spacing.xxl),

        // ── Low stock alert ──
        _buildLowStockAlert(context, ref, data.lowStockProducts),
        const SizedBox(height: Spacing.xxl),

        // ── Recent sales ──
        _buildRecentSalesCard(
          context,
          data.recentSales.isNotEmpty
              ? data.recentSales
              : data.analytics.sales.take(5).toList(),
          title: 'Recent Sales',
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Announcements ──
        if (data.announcements.isNotEmpty) ...[
          _buildAnnouncementsCard(context, data.announcements),
          const SizedBox(height: Spacing.xxl),
        ],

        // ── Recent activity ──
        _buildRecentActivityCard(context, data.recentActivities),
        const SizedBox(height: Spacing.xxl),

        // ── AI Advisor entry ──
        if (authNotifier.hasPermission('view_ai_advisor')) ...[
          _buildAIAdvisorCard(context, ref),
          const SizedBox(height: Spacing.xxl),
        ],
      ],
    );
  }

  Widget _buildSalesTrendCard(
    BuildContext context,
    SalesAnalytics analytics,
    String currencySymbol,
  ) {
    return AppSection(
      title: 'Sales Trend',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: analytics.trend.isEmpty
            ? const _ChartEmptyState(
                message: 'No sales data available for this period.',
              )
            : SalesLineChart(
                points: analytics.trend,
                groupBy: analytics.bounds.groupBy,
                valuePrefix: currencySymbol,
              ),
      ),
    );
  }

  Widget _buildComparisonChart(
    BuildContext context,
    SalesAnalytics analytics,
    String currencySymbol,
  ) {
    return AppSection(
      title: 'Period Comparison',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: analytics.trend.isEmpty && analytics.previousTrend.isEmpty
            ? const _ChartEmptyState(
                message: 'No comparison data available.',
              )
            : SalesComparisonChart(
                current: analytics.trend,
                previous: analytics.previousTrend,
                groupBy: analytics.bounds.groupBy,
                valuePrefix: currencySymbol,
              ),
      ),
    );
  }

  Widget _buildPaymentAndTopProducts(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    return AppSection(
      title: 'Payment & Top Products',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: _ResponsiveTwoColumn(
        left: AppCard(
          child: PaymentBreakdownView(
            breakdown: analytics.paymentBreakdown,
            grandTotal: analytics.totalSales,
          ),
        ),
        right: AppCard(
          child: TopProductsBarChart(
            products: analytics.topProducts,
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySalesCard(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    return AppSection(
      title: 'Sales by Category',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: CategorySalesBarChart(
          categorySales: analytics.categorySales,
        ),
      ),
    );
  }

  Widget _buildStaffPerformanceSection(
    BuildContext context,
    List<StaffSalesSummary> summaries,
  ) {
    return AppSection(
      title: 'Staff Performance',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: StaffPerformanceList(
        staff: summaries,
        storeInfo: null,
      ),
    );
  }

  Widget _buildPeakSalesCard(
    BuildContext context,
    PeakSalesPeriod peak,
  ) {
    return AppSection(
      title: 'Peak Sales',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: PeakSalesCard(peak: peak),
      ),
    );
  }

  Widget _buildLowStockAlert(
    BuildContext context,
    WidgetRef ref,
    List<Product> products,
  ) {
    if (products.isEmpty) {
      return AppSection(
        title: 'Low Stock Alert',
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: AppCard(
          child: Row(
            children: [
              Icon(Icons.check_circle,
                  color: AppSemanticColors.resolve(
                      AppSemanticColors.success,
                      Theme.of(context).brightness)),
              const SizedBox(width: Spacing.md),
              const Expanded(child: Text('Inventory is healthy')),
            ],
          ),
        ),
      );
    }
    return AppSection(
      title: 'Low Stock Alert',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...products.take(5).map((p) => _LowStockTile(
                  name: p.name,
                  remaining: p.stock,
                )),
            if (ref
                .read(authStateProvider.notifier)
                .hasPermission('add_stock')) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton.text(
                  color: AppButtonColor.info,
                  onPressed: () => RouteGuard.pushIfAuthorized(
                    context, ref,
                    screen: const StockScreen(),
                    permission: 'add_stock',
                    routeName: 'stock',
                  ),
                  icon: Icons.warehouse_outlined,
                  label: 'View Stock',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSalesCard(
    BuildContext context,
    List<Sale> sales,
    {required String title}
  ) {
    return AppSection(
      title: title,
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: sales.isEmpty
            ? const _ChartEmptyState(message: 'No sales recorded yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sales.take(5).map((s) => _RecentSaleTile(
                      receipt: '#${s.receiptNumber ?? s.id}',
                      amount: CurrencyUtils.format(s.totalAmount),
                      time: _formatDateTime(s.createdAt),
                    )).toList(),
              ),
      ),
    );
  }

  Widget _buildAnnouncementsCard(
    BuildContext context,
    List<Announcement> announcements,
  ) {
    return AppSection(
      title: 'Announcements',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...announcements.take(3).map((a) => _AnnouncementTile(
                  title: a.title,
                  content: a.content,
                  isPinned: a.isPinned,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return AppSection(
      title: 'Recent Activity',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: activities.isEmpty
            ? const _ChartEmptyState(message: 'No activity yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: activities.take(5).map((a) => _ActivityTile(
                      action: _humanizeAction(a.action),
                      details: a.details,
                      time: _formatDateTime(a.createdAt),
                    )).toList(),
              ),
      ),
    );
  }

  Widget _buildAIAdvisorCard(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return AppSection(
      title: 'Business Advisor',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        onTap: () => RouteGuard.pushIfAuthorized(
          context, ref,
          screen: const AIAdvisorScreen(),
          permission: 'view_ai_advisor',
          routeName: 'ai_advisor',
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: cs.tertiary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Analyze your latest sales and inventory.',
                style: AppTypography.bodySmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return AppSection(
      title: 'Quick Actions',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        children: [
          if (authNotifier.hasPermission('create_sales'))
            _QuickAction(
              label: 'New Sale',
              color: AppButtonColor.success,
              icon: Icons.point_of_sale,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const POSScreen(),
                permission: 'create_sales',
                routeName: 'pos_new_sale',
              ),
            ),
          if (authNotifier.hasPermission('edit_products'))
            _QuickAction(
              label: 'Add Product',
              color: AppButtonColor.info,
              icon: Icons.add_box_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const ProductsScreen(),
                permission: 'edit_products',
                routeName: 'products',
              ),
            ),
          if (authNotifier.hasPermission('add_stock'))
            _QuickAction(
              label: 'Add Stock',
              color: AppButtonColor.warning,
              icon: Icons.warehouse_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const StockScreen(),
                permission: 'add_stock',
                routeName: 'stock',
              ),
            ),
          if (authNotifier.hasPermission('view_sales'))
            _QuickAction(
              label: 'View Sales',
              color: AppButtonColor.neutral,
              icon: Icons.receipt_long,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const SalesScreen(),
                permission: 'view_sales',
                routeName: 'sales',
              ),
            ),
          if (authNotifier.hasPermission('view_reports'))
            _QuickAction(
              label: 'Reports',
              color: AppButtonColor.neutral,
              icon: Icons.analytics_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const SalesAnalyticsScreen(),
                permission: 'view_reports',
                routeName: 'reports',
              ),
            ),
          if (authNotifier.hasPermission('manage_staff'))
            _QuickAction(
              label: 'Manage Staff',
              color: AppButtonColor.info,
              icon: Icons.people,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const StaffManagementScreen(),
                permission: 'manage_staff',
                routeName: 'staff_management',
              ),
            ),
          if (authNotifier.hasPermission('view_ai_advisor'))
            _QuickAction(
              label: 'AI Advisor',
              icon: Icons.auto_awesome,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const AIAdvisorScreen(),
                permission: 'view_ai_advisor',
                routeName: 'ai_advisor',
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Admin Dashboard
// ─────────────────────────────────────────────────────────────────────────

class _AdminDashboard extends ConsumerWidget {
  final AdminDashboardData data;
  const _AdminDashboard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── System KPIs ──
        AppSection(
          title: 'System Overview',
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: KpiGrid(
            children: [
              KpiCard(
                label: 'Active Users',
                value: '${data.activeUsers}',
                icon: Icons.person_outline,
                iconColor: AppSemanticColors.resolve(
                  AppSemanticColors.success,
                  Theme.of(context).brightness,
                ),
                tier: KpiCardTier.primary,
              ),
              KpiCard(
                label: 'Inactive Users',
                value: '${data.inactiveUsers}',
                icon: Icons.person_off_outlined,
                iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                tier: KpiCardTier.secondary,
              ),
              KpiCard(
                label: 'Recent Activity',
                value: '${data.recentActivityCount}',
                icon: Icons.history,
                iconColor: Theme.of(context).colorScheme.tertiary,
                subtitle: 'last 7 days',
                tier: KpiCardTier.secondary,
              ),
              KpiCard(
                label: 'Trash Items',
                value: '${data.trashCount}',
                icon: Icons.delete_outline,
                iconColor: AppSemanticColors.resolve(
                  AppSemanticColors.warning,
                  Theme.of(context).brightness,
                ),
                tier: KpiCardTier.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Quick actions ──
        _buildAdminQuickActions(context, ref, authNotifier),
        const SizedBox(height: Spacing.xxl),

        // ── Two-column: user distribution + backup status ──
        _ResponsiveTwoColumn(
          left: _buildUserDistributionCard(context),
          right: _buildBackupCard(context),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Two-column: export history + AI service status ──
        _ResponsiveTwoColumn(
          left: _buildExportHistoryCard(context),
          right: _buildAiStatusCard(context),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Recent activity ──
        _buildRecentActivityCard(context, data.recentActivities),
      ],
    );
  }

  Widget _buildExportHistoryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSection(
      title: 'Export History',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.file_download_outlined, color: cs.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    '${data.exportCount} report${data.exportCount == 1 ? '' : 's'} exported',
                    style: AppTypography.bodyMedium(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              data.lastExportAt != null
                  ? 'Latest: ${DateFormat('MMM d, y \u00b7 h:mm a').format(data.lastExportAt!.toLocal())}'
                  : 'No reports exported yet.',
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiStatusCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return AppSection(
      title: 'AI Service',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  data.aiConfigured
                      ? Icons.check_circle
                      : Icons.warning_amber_outlined,
                  color: AppSemanticColors.resolve(
                    data.aiConfigured
                        ? AppSemanticColors.success
                        : AppSemanticColors.warning,
                    brightness,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    data.aiConfigured
                        ? 'Groq API configured'
                        : 'No Groq API key configured',
                    style: AppTypography.bodyMedium(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              data.aiConfigured ? 'Model: ${data.aiModel}' : 'AI Advisor is offline.',
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${data.aiQueriesToday} quer${data.aiQueriesToday == 1 ? 'y' : 'ies'} today',
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDistributionCard(BuildContext context) {
    return AppSection(
      title: 'Users by Role',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.usersByRole.total == 0)
              const _ChartEmptyState(message: 'No users yet.')
            else
              DonutChart(
                segments: [
                  DonutSegment(
                    label: 'Owner',
                    value: data.usersByRole.owner,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  DonutSegment(
                    label: 'Admin',
                    value: data.usersByRole.admin,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  DonutSegment(
                    label: 'Staff',
                    value: data.usersByRole.staff,
                    color: AppSemanticColors.resolve(
                      AppSemanticColors.info,
                      Theme.of(context).brightness,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSection(
      title: 'Backup Status',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.backupStatus.hasBackup &&
                data.backupStatus.lastBackupDate != null)
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppSemanticColors.resolve(
                          AppSemanticColors.success,
                          Theme.of(context).brightness)),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Latest: ${DateFormat('MMM d, y \u00b7 h:mm a').format(data.backupStatus.lastBackupDate!.toLocal())}',
                      style: AppTypography.bodyMedium(context),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'No backup has been created yet.',
                      style: AppTypography.bodyMedium(context),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return AppSection(
      title: 'Recent System Activity',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: activities.isEmpty
            ? const _ChartEmptyState(message: 'No activity yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: activities.take(5).map((a) => _ActivityTile(
                      action: _humanizeAction(a.action),
                      details: a.details,
                      time: _formatDateTime(a.createdAt),
                    )).toList(),
              ),
      ),
    );
  }

  Widget _buildAdminQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return AppSection(
      title: 'Quick Actions',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        children: [
          if (authNotifier.hasPermission('manage_users'))
            _QuickAction(
              label: 'Manage Users',
              color: AppButtonColor.info,
              icon: Icons.people,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const UsersScreen(),
                permission: 'manage_users',
                routeName: 'users',
              ),
            ),
          if (authNotifier.hasPermission('backup_restore'))
            _QuickAction(
              label: 'Backup & Restore',
              color: AppButtonColor.neutral,
              icon: Icons.backup,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const BackupRestoreScreen(),
                permission: 'backup_restore',
                routeName: 'backup_restore',
              ),
            ),
          if (authNotifier.hasPermission('view_trash'))
            _QuickAction(
              label: 'Trash',
              color: AppButtonColor.warning,
              icon: Icons.delete_outline,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const TrashScreen(),
                permission: 'view_trash',
                routeName: 'trash',
              ),
            ),
          if (authNotifier.hasPermission('view_activity_logs'))
            _QuickAction(
              label: 'Activity Logs',
              color: AppButtonColor.neutral,
              icon: Icons.history,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const ActivityLogsScreen(),
                permission: 'view_activity_logs',
                routeName: 'activity_logs',
              ),
            ),
          if (authNotifier.hasPermission('manage_ai_config'))
            _QuickAction(
              label: 'AI Config',
              color: AppButtonColor.info,
              icon: Icons.psychology_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const AIConfigScreen(),
                permission: 'manage_ai_config',
                routeName: 'ai_config',
              ),
            ),
          if (authNotifier.hasPermission('view_settings'))
            _QuickAction(
              label: 'Settings',
              color: AppButtonColor.neutral,
              icon: Icons.settings,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const SettingsScreen(),
                permission: 'view_settings',
                routeName: 'settings',
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Staff Dashboard
// ─────────────────────────────────────────────────────────────────────────

class _StaffDashboard extends ConsumerWidget {
  final StaffDashboardData data;
  const _StaffDashboard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = data.analytics;
    final currencySymbol = CurrencyUtils.symbol();
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary KPIs (own sales only) ──
        AppSection(
          title: 'My Performance',
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: SalesSummaryCards(
            analytics: analytics,
            storeInfo: null,
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Quick actions ──
        _buildStaffQuickActions(context, ref, authNotifier),
        const SizedBox(height: Spacing.xxl),

        // ── My sales trend ──
        _buildSalesTrendCard(
          context,
          analytics,
          currencySymbol,
          title: 'My Sales Trend',
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Top products ──
        _buildTopProductsCard(context, analytics),
        const SizedBox(height: Spacing.xxl),

        // ── Payment breakdown ──
        _buildPaymentBreakdown(context, analytics),
        const SizedBox(height: Spacing.xxl),

        // ── Peak sales ──
        _buildPeakSalesCard(context, analytics.peakSalesPeriod),
        const SizedBox(height: Spacing.xxl),

        // ── Inventory status ──
        _buildInventoryCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Low stock alert ──
        _buildLowStockAlert(context, ref, data.lowStockProducts),
        const SizedBox(height: Spacing.xxl),

        // ── Recent activity (own) ──
        _buildRecentActivityCard(context, data.recentActivities),
      ],
    );
  }

  Widget _buildSalesTrendCard(
    BuildContext context,
    SalesAnalytics analytics,
    String currencySymbol, {
    required String title,
  }) {
    return AppSection(
      title: title,
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: analytics.trend.isEmpty
            ? const _ChartEmptyState(
                message: 'No sales data available for this period.',
              )
            : SalesLineChart(
                points: analytics.trend,
                groupBy: analytics.bounds.groupBy,
                valuePrefix: currencySymbol,
              ),
      ),
    );
  }

  Widget _buildTopProductsCard(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    return AppSection(
      title: 'Top Products',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: TopProductsBarChart(
          products: analytics.topProducts,
        ),
      ),
    );
  }

  Widget _buildPaymentBreakdown(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    return AppSection(
      title: 'Payment Breakdown',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: PaymentBreakdownView(
          breakdown: analytics.paymentBreakdown,
          grandTotal: analytics.totalSales,
        ),
      ),
    );
  }

  Widget _buildPeakSalesCard(
    BuildContext context,
    PeakSalesPeriod peak,
  ) {
    return AppSection(
      title: 'Peak Sales',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: PeakSalesCard(peak: peak),
      ),
    );
  }

  Widget _buildInventoryCard(BuildContext context) {
    return AppSection(
      title: 'Inventory Status',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.inventoryStatus.total == 0)
              const _ChartEmptyState(message: 'No products yet.')
            else
              DonutChart(
                segments: [
                  DonutSegment(
                    label: 'Normal',
                    value: data.inventoryStatus.normal,
                    color: AppSemanticColors.resolve(
                        AppSemanticColors.success,
                        Theme.of(context).brightness),
                  ),
                  DonutSegment(
                    label: 'Low Stock',
                    value: data.inventoryStatus.lowStock,
                    color: AppSemanticColors.resolve(
                        AppSemanticColors.warning,
                        Theme.of(context).brightness),
                  ),
                  DonutSegment(
                    label: 'Out of Stock',
                    value: data.inventoryStatus.outOfStock,
                    color: AppSemanticColors.resolve(
                        AppSemanticColors.error,
                        Theme.of(context).brightness),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockAlert(
    BuildContext context,
    WidgetRef ref,
    List<Product> products,
  ) {
    if (products.isEmpty) {
      return AppSection(
        title: 'Low Stock Alert',
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: AppCard(
          child: Row(
            children: [
              Icon(Icons.check_circle,
                  color: AppSemanticColors.resolve(
                      AppSemanticColors.success,
                      Theme.of(context).brightness)),
              const SizedBox(width: Spacing.md),
              const Expanded(child: Text('Inventory is healthy')),
            ],
          ),
        ),
      );
    }
    return AppSection(
      title: 'Low Stock Alert',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...products.take(5).map((p) => _LowStockTile(
                  name: p.name,
                  remaining: p.stock,
                )),
            if (ref
                .read(authStateProvider.notifier)
                .hasPermission('add_stock')) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton.text(
                  color: AppButtonColor.info,
                  onPressed: () => RouteGuard.pushIfAuthorized(
                    context, ref,
                    screen: const StockScreen(),
                    permission: 'add_stock',
                    routeName: 'stock',
                  ),
                  icon: Icons.warehouse_outlined,
                  label: 'View Stock',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return AppSection(
      title: 'Recent Activity',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        child: activities.isEmpty
            ? const _ChartEmptyState(message: 'No activity yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: activities.take(5).map((a) => _ActivityTile(
                      action: _humanizeAction(a.action),
                      details: a.details,
                      time: _formatDateTime(a.createdAt),
                    )).toList(),
              ),
      ),
    );
  }

  Widget _buildStaffQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return AppSection(
      title: 'Quick Actions',
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        children: [
          if (authNotifier.hasPermission('create_sales'))
            _QuickAction(
              label: 'New Sale',
              color: AppButtonColor.success,
              icon: Icons.point_of_sale,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const POSScreen(),
                permission: 'create_sales',
                routeName: 'pos_new_sale',
              ),
            ),
          if (authNotifier.hasPermission('add_stock'))
            _QuickAction(
              label: 'Add Stock',
              color: AppButtonColor.warning,
              icon: Icons.warehouse_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const StockScreen(),
                permission: 'add_stock',
                routeName: 'stock',
              ),
            ),
          if (authNotifier.hasPermission('view_sales'))
            _QuickAction(
              label: 'My Sales',
              color: AppButtonColor.neutral,
              icon: Icons.receipt_long,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const SalesScreen(),
                permission: 'view_sales',
                routeName: 'sales',
              ),
            ),
          if (authNotifier.hasPermission('view_reports'))
            _QuickAction(
              label: 'Reports',
              color: AppButtonColor.neutral,
              icon: Icons.analytics_outlined,
              onTap: () => RouteGuard.pushIfAuthorized(
                context, ref,
                screen: const SalesAnalyticsScreen(),
                permission: 'view_reports',
                routeName: 'reports',
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Small reusable tiles
// ─────────────────────────────────────────────────────────────────────────

class _ChartEmptyState extends StatelessWidget {
  final String message;
  const _ChartEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 32, color: cs.outline),
          const SizedBox(height: Spacing.sm),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final String name;
  final int remaining;

  const _LowStockTile({required this.name, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 8,
              color: AppSemanticColors.resolve(
                  AppSemanticColors.warning,
                  Theme.of(context).brightness)),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$remaining remaining',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppSemanticColors.resolve(
                      AppSemanticColors.warning,
                      Theme.of(context).brightness),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  final String receipt;
  final String amount;
  final String time;

  const _RecentSaleTile({
    required this.receipt,
    required this.amount,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Icon(Icons.receipt_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(receipt, style: Theme.of(context).textTheme.bodyMedium),
                Text(time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          Text(
            amount,
            style: AppTypography.titleSmallBold(context),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  final String title;
  final String content;
  final bool isPinned;

  const _AnnouncementTile({
    required this.title,
    required this.content,
    required this.isPinned,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPinned)
            Icon(Icons.push_pin, size: 16, color: cs.primary)
          else
            Icon(Icons.campaign_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(content,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String action;
  final String? details;
  final String time;

  const _ActivityTile({
    required this.action,
    this.details,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action, style: Theme.of(context).textTheme.bodyMedium),
                if (details != null)
                  Text(details!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                Text(time,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final AppButtonColor color;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = AppButtonColor.primary,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton.quickAction(
      onPressed: onTap,
      color: color,
      icon: icon,
      label: label,
    );
  }
}


/// Two-column layout that stacks vertically on mobile and goes side-by-side
/// on tablet/desktop (≥600px). Each column gets equal width.
class _ResponsiveTwoColumn extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsiveTwoColumn({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    if (!isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          left,
          const SizedBox(height: Spacing.lg),
          right,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: Spacing.lg),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// Converts a raw activity-log action string (e.g. "create_product") into a
/// human-readable label (e.g. "Created product"). Falls back to the raw
/// action if no mapping is known.
String _humanizeAction(String action) {
  final map = <String, String>{
    'create_product': 'Created product',
    'update_product': 'Updated product',
    'delete_product': 'Deleted product',
    'restore_product': 'Restored product',
    'permanently_delete_product': 'Permanently deleted product',
    'add_stock': 'Added stock',
    'adjust_stock': 'Adjusted stock',
    'create_sale': 'Created sale',
    'void_sale': 'Voided sale',
    'create_announcement': 'Created announcement',
    'update_announcement': 'Updated announcement',
    'delete_announcement': 'Deleted announcement',
    'create_user': 'Created user',
    'update_user': 'Updated user',
    'delete_user': 'Deleted user',
    'restore_user': 'Restored user',
    'toggle_user_active': 'Toggled user status',
    'create_backup': 'Created backup',
    'restore_backup': 'Restored backup',
    'login': 'Signed in',
    'logout': 'Signed out',
    'update_profile': 'Updated profile',
    'update_settings': 'Updated settings',
    'unauthorized_access': 'Unauthorized access attempt',
  };
  return map[action] ?? action.replaceAll('_', ' ');
}
