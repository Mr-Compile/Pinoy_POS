import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/dashboard_provider.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';
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
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_config_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/dashboard_blocks.dart';
import 'package:pinoy_pos/ui/widgets/donut_chart.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/mini_bar_chart.dart';
import 'package:pinoy_pos/ui/widgets/sales_period_selector.dart';

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

  String _subtitle(User? user, String? storeName) {
    return switch (user?.role) {
      UserRole.owner =>
        'Pinoy POS${storeName != null && storeName.isNotEmpty ? ' · $storeName' : ''}',
      UserRole.admin => 'System Overview',
      UserRole.staff => 'My Work',
      null => '',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final dashboardState = ref.watch(dashboardProvider);
    final storeName = ref.watch(settingsProvider).valueOrNull?.storeName;

    return Scaffold(
      appBar: AppHeader(
        title: 'Dashboard',
        subtitle: _subtitle(user, storeName),
      ),
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

  const _DashboardLoadedView({this.user, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return const Center(child: Text('Not authenticated'));
    }

    final isAdmin = data is AdminDashboardData;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardWelcome(user: user!),
          const SizedBox(height: Spacing.lg),
          if (!isAdmin) ...[
            const SalesPeriodSelector(),
            const SizedBox(height: Spacing.lg),
          ],
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
// Denied view
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
    final greeting =
        user?.role == UserRole.admin ? 'Welcome back' : null;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user != null)
            DashboardWelcome(user: user!, greeting: greeting)
          else
            _skeletonBox(context, height: 58, width: 200),
          const SizedBox(height: Spacing.lg),
          _skeletonBox(context, height: 36, width: double.infinity),
          const SizedBox(height: Spacing.md),
          _skeletonBox(context, height: 48, width: double.infinity),
          const SizedBox(height: Spacing.lg),
          _skeletonBox(context, height: 150, width: double.infinity),
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              Expanded(child: _skeletonBox(context, height: 78)),
              const SizedBox(width: 10),
              Expanded(child: _skeletonBox(context, height: 78)),
              const SizedBox(width: 10),
              Expanded(child: _skeletonBox(context, height: 78)),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _skeletonBox(context, height: 120, width: double.infinity),
        ],
      ),
    );
  }

  Widget _skeletonBox(BuildContext context,
      {required double height, double? width}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
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
    final filter = ref.watch(salesPeriodFilterProvider);
    final authNotifier = ref.read(authStateProvider.notifier);

    final changePct =
        analytics.comparison.totalChangePercent(analytics.totalSales);
    final sparkValues =
        analytics.trend.map((p) => p.total).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroKpiCard(
          icon: Icons.payments_outlined,
          label: 'Total Sales · ${_trendPillLabel(filter)}',
          amount: CurrencyUtils.format(analytics.totalSales),
          deltaPercent: changePct,
          deltaSuffix: _deltaSuffix(filter),
          sparkValues: sparkValues,
          footStats: [
            HeroFootStat('${analytics.transactionCount}', 'transactions'),
            HeroFootStat('${analytics.itemsSold}', 'items sold'),
            HeroFootStat(
              CurrencyUtils.formatWhole(analytics.averageTransaction),
              'avg sale',
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        StatStrip(
          items: [
            StatItem(
              icon: Icons.receipt_long,
              accent: DashAccent.blue,
              value: '${analytics.transactionCount}',
              label: 'Transactions',
            ),
            StatItem(
              icon: Icons.shopping_basket_outlined,
              accent: DashAccent.teal,
              value: '${analytics.itemsSold}',
              label: 'Items sold',
            ),
            StatItem(
              icon: Icons.trending_up,
              accent: DashAccent.green,
              value: CurrencyUtils.formatWhole(analytics.averageTransaction),
              label: 'Avg sale',
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        _buildQuickActionsCard(context, ref, authNotifier),
        const SizedBox(height: Spacing.lg),
        _buildSalesTrendCard(context, analytics, filter),
        const SizedBox(height: Spacing.lg),
        _buildPaymentMethodsCard(context, analytics),
        const SizedBox(height: Spacing.lg),
        _buildTopProductsCard(context, analytics),
        const SizedBox(height: Spacing.lg),
        _buildStaffPerformanceCard(context, analytics),
        const SizedBox(height: Spacing.lg),
        _buildLowStockCard(
          context,
          ref,
          data.lowStockProducts,
          data.categoryNames,
        ),
        const SizedBox(height: Spacing.lg),
        _buildRecentSalesCard(context, data),
        const SizedBox(height: Spacing.lg),
        _buildAnnouncementsCard(context, data.announcements),
        const SizedBox(height: Spacing.lg),
        _buildRecentActivityCard(context, data.recentActivities),
        const SizedBox(height: Spacing.lg),
        if (authNotifier.hasPermission('view_ai_advisor')) ...[
          AdvisorBanner(
            icon: Icons.auto_awesome,
            title: 'Business Advisor',
            subtitle: 'Analyze your latest sales and inventory.',
            onTap: () => RouteGuard.pushIfAuthorized(
              context, ref,
              screen: const AIAdvisorScreen(),
              permission: 'view_ai_advisor',
              routeName: 'ai_advisor',
            ),
          ),
          const SizedBox(height: Spacing.lg),
        ],
      ],
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    WidgetRef ref,
    AuthStateNotifier authNotifier,
  ) {
    final children = <Widget>[
      if (authNotifier.hasPermission('create_sales'))
        QuickActionTile(
          icon: Icons.point_of_sale,
          label: 'New Sale',
          primary: true,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const POSScreen(),
            permission: 'create_sales',
            routeName: 'pos_new_sale',
          ),
        ),
      if (authNotifier.hasPermission('edit_products'))
        QuickActionTile(
          icon: Icons.add_box_outlined,
          label: 'Add Product',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const ProductsScreen(),
            permission: 'edit_products',
            routeName: 'products',
          ),
        ),
      if (authNotifier.hasPermission('add_stock'))
        QuickActionTile(
          icon: Icons.warehouse_outlined,
          label: 'Add Stock',
          accent: DashAccent.amber,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const StockScreen(),
            permission: 'add_stock',
            routeName: 'stock',
          ),
        ),
      if (authNotifier.hasPermission('view_sales'))
        QuickActionTile(
          icon: Icons.receipt_long,
          label: 'View Sales',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const SalesScreen(),
            permission: 'view_sales',
            routeName: 'sales',
          ),
        ),
      if (authNotifier.hasPermission('view_reports'))
        QuickActionTile(
          icon: Icons.bar_chart,
          label: 'Reports',
          accent: DashAccent.deep,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const SalesAnalyticsScreen(),
            permission: 'view_reports',
            routeName: 'reports',
          ),
        ),
      if (authNotifier.hasPermission('manage_staff'))
        QuickActionTile(
          icon: Icons.people,
          label: 'Manage Staff',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const StaffManagementScreen(),
            permission: 'manage_staff',
            routeName: 'staff_management',
          ),
        ),
      if (authNotifier.hasPermission('view_ai_advisor'))
        QuickActionTile(
          icon: Icons.auto_awesome,
          label: 'AI Advisor',
          accent: DashAccent.deep,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const AIAdvisorScreen(),
            permission: 'view_ai_advisor',
            routeName: 'ai_advisor',
          ),
        ),
    ];
    return DashCard(
      title: '',
      children: [QuickActionPanel(columns: 4, children: children)],
    );
  }

  Widget _buildSalesTrendCard(
    BuildContext context,
    SalesAnalytics analytics,
    SalesPeriodFilter filter,
  ) {
    if (analytics.trend.isEmpty || _trendIsAllZero(analytics.trend)) {
      return DashCard(
        title: 'Sales Trend',
        icon: Icons.bar_chart,
        iconAccent: DashAccent.blue,
        trailing: _TrendPill(filter: filter),
        children: const [Center(child: Text('No sales recorded this period.'))],
      );
    }

    final points = analytics.trend
        .map((p) => _toBarPoint(p, filter.period))
        .toList();
    final highlightIndex = _highlightIndex(points);

    return DashCard(
      title: 'Sales Trend',
      icon: Icons.bar_chart,
      iconAccent: DashAccent.blue,
      trailing: _TrendPill(filter: filter),
      children: [
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _buildTrendBars(context, points, highlightIndex),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _buildTrendLabels(context, points),
        ),
        const SizedBox(height: Spacing.xs),
        _buildTrendLegend(context),
      ],
    );
  }

  Widget _buildPaymentMethodsCard(BuildContext context, SalesAnalytics analytics) {
    final total = analytics.totalSales;
    final breakdown = analytics.paymentBreakdown;

    if (breakdown.isEmpty) {
      return const DashCard(
        title: 'Payment Methods',
        children: [Text('No payment data this period.')],
      );
    }

    return DashCard(
      title: 'Payment Methods',
      children: _paymentRows(context, breakdown, total),
    );
  }

  Widget _buildTopProductsCard(BuildContext context, SalesAnalytics analytics) {
    final products = analytics.topProducts;
    if (products.isEmpty) {
      return const DashCard(
        title: 'Top Products',
        children: [Text('No products sold this period.')],
      );
    }

    return DashCard(
      title: 'Top Products',
      children: _topProductRows(context, products),
    );
  }

  Widget _buildStaffPerformanceCard(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    final summaries = analytics.staffSummaries.take(3).toList();
    if (summaries.isEmpty) {
      return const DashCard(
        title: 'Staff Performance',
        children: [Text('No staff sales this period.')],
      );
    }

    return DashCard(
      title: 'Staff Performance',
      children: _staffRows(context, summaries, analytics.sales),
    );
  }

  Widget _buildLowStockCard(
    BuildContext context,
    WidgetRef ref,
    List<Product> products,
    Map<int, String> categoryNames,
  ) {
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);

    return DashCard(
      title: 'Low Stock Alert',
      icon: Icons.warehouse_outlined,
      iconAccent: DashAccent.amber,
      alert: products.isNotEmpty,
      trailing: products.isNotEmpty
          ? StatusPill(
              label: '${products.length} items',
              color: AppSemanticColors.resolve(
                  AppSemanticColors.warning, cs.brightness),
            )
          : null,
      children: [
        if (products.isEmpty)
          Row(
            children: [
              IconBadge(
                icon: Icons.check_circle,
                color: AppSemanticColors.resolve(
                    AppSemanticColors.success, cs.brightness),
                size: 32,
                iconSize: 15,
                filled: false,
              ),
              const SizedBox(width: Spacing.md),
              const Text('Inventory is healthy'),
            ],
          )
        else
          ..._lowStockRows(context, products, categoryNames),
        if (products.isNotEmpty && authNotifier.hasPermission('add_stock'))
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: InkWell(
                onTap: () => RouteGuard.pushIfAuthorized(
                  context, ref,
                  screen: const StockScreen(),
                  permission: 'add_stock',
                  routeName: 'stock',
                ),
                child: Text(
                  'View Stock →',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: AppSemanticColors.resolve(
                      AppSemanticColors.info,
                      cs.brightness,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentSalesCard(BuildContext context, OwnerDashboardData data) {
    final sales = data.recentSales.isNotEmpty
        ? data.recentSales
        : data.analytics.sales.take(5).toList();
    final count = sales.length;

    return DashCard(
      title: 'Recent Sales',
      trailing: StatusPill(
        label: '$count',
        color: AppSemanticColors.resolve(
          AppSemanticColors.info,
          Theme.of(context).brightness,
        ),
      ),
      children: sales.isEmpty
          ? const [Text('No sales recorded yet.')]
          : _saleRows(context, sales),
    );
  }

  Widget _buildAnnouncementsCard(
    BuildContext context,
    List<Announcement> announcements,
  ) {
    if (announcements.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final a in announcements.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.lg),
            child: DashCard(
              title: 'Announcement',
              icon: Icons.push_pin,
              iconAccent: DashAccent.amber,
              elevated: true,
              trailing: StatusPill(
                label: a.isPinned ? 'Pinned' : 'Active',
                color: AppSemanticColors.resolve(
                    AppSemanticColors.warning,
                    Theme.of(context).brightness),
              ),
              children: [
                Text(
                  a.content,
                  style: AppTypography.bodyMedium(context),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return DashCard(
      title: 'Recent Activity',
      children: activities.isEmpty
          ? const [Text('No activity yet.')]
          : _activityRows(context, activities),
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
        StatStrip(
          columns: 2,
          items: [
            StatItem(
              icon: Icons.person_outline,
              accent: DashAccent.green,
              value: '${data.activeUsers}',
              label: 'Active Users',
            ),
            StatItem(
              icon: Icons.person_off_outlined,
              accent: DashAccent.grey,
              value: '${data.inactiveUsers}',
              label: 'Inactive Users',
            ),
            StatItem(
              icon: Icons.history,
              accent: DashAccent.blue,
              value: '${data.recentActivityCount}',
              label: 'Recent activity',
            ),
            StatItem(
              icon: Icons.delete_outline,
              accent: DashAccent.amber,
              value: '${data.trashCount}',
              label: 'Trash Items',
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        _buildQuickActionsCard(context, ref, authNotifier),
        const SizedBox(height: Spacing.lg),
        _buildUsersByRoleCard(context),
        const SizedBox(height: Spacing.lg),
        _buildSystemHealthCard(context),
        const SizedBox(height: Spacing.lg),
        _buildNeedsAttentionCard(context),
        const SizedBox(height: Spacing.lg),
        _buildRecentActivityCard(context, data.recentActivities),
      ],
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    WidgetRef ref,
    AuthStateNotifier authNotifier,
  ) {
    final children = <Widget>[
      if (authNotifier.hasPermission('manage_users'))
        QuickActionTile(
          icon: Icons.people,
          label: 'Manage Users',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const UsersScreen(),
            permission: 'manage_users',
            routeName: 'users',
          ),
        ),
      if (authNotifier.hasPermission('backup_restore'))
        QuickActionTile(
          icon: Icons.backup,
          label: 'Backup',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const BackupRestoreScreen(),
            permission: 'backup_restore',
            routeName: 'backup_restore',
          ),
        ),
      if (authNotifier.hasPermission('view_trash'))
        QuickActionTile(
          icon: Icons.delete_outline,
          label: 'Trash',
          accent: DashAccent.amber,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const TrashScreen(),
            permission: 'view_trash',
            routeName: 'trash',
          ),
        ),
      if (authNotifier.hasPermission('view_activity_logs'))
        QuickActionTile(
          icon: Icons.history,
          label: 'Activity Logs',
          accent: DashAccent.grey,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const ActivityLogsScreen(),
            permission: 'view_activity_logs',
            routeName: 'activity_logs',
          ),
        ),
      if (authNotifier.hasPermission('manage_ai_config'))
        QuickActionTile(
          icon: Icons.auto_awesome,
          label: 'AI Config',
          accent: DashAccent.deep,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const AIConfigScreen(),
            permission: 'manage_ai_config',
            routeName: 'ai_config',
          ),
        ),
      if (authNotifier.hasPermission('view_settings'))
        QuickActionTile(
          icon: Icons.settings,
          label: 'Settings',
          accent: DashAccent.grey,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const SettingsScreen(),
            permission: 'view_settings',
            routeName: 'settings',
          ),
        ),
    ];
    return DashCard(
      title: '',
      children: [QuickActionPanel(columns: 3, children: children)],
    );
  }

  Widget _buildUsersByRoleCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = data.usersByRole.total;
    return DashCard(
      title: 'Users by Role',
      children: [
        if (total == 0)
          const Text('No users yet.')
        else
          DonutChart(
            size: 110,
            segments: [
              DonutSegment(
                label: 'Owner',
                value: data.usersByRole.owner,
                color: cs.primary,
              ),
              DonutSegment(
                label: 'Admin',
                value: data.usersByRole.admin,
                color: AppSemanticColors.resolve(
                    AppSemanticColors.info, cs.brightness),
              ),
              DonutSegment(
                label: 'Staff',
                value: data.usersByRole.staff,
                color: AppSemanticColors.resolve(
                    AppSemanticColors.neutral, cs.brightness),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSystemHealthCard(BuildContext context) {
    final b = Theme.of(context).brightness;

    final backupOk = data.backupStatus.hasBackup;
    final aiOk = data.aiConfigured;
    final exports = data.exportCount;

    return DashCard(
      title: 'System Health',
      children: [
        DashRow(
          leading: IconBadge(
            icon: backupOk ? Icons.check_circle : Icons.warning_amber_outlined,
            color: backupOk
                ? AppSemanticColors.resolve(AppSemanticColors.success, b)
                : AppSemanticColors.resolve(AppSemanticColors.warning, b),
            size: 34,
            iconSize: 17,
            filled: false,
          ),
          title: backupOk ? 'Backup up to date' : 'No backup created yet',
          subtitle: backupOk && data.backupStatus.lastBackupDate != null
              ? 'Latest: ${DateFormat('MMM d, y \u00b7 h:mm a').format(data.backupStatus.lastBackupDate!.toLocal())}'
              : null,
          showDivider: false,
        ),
        DashRow(
          leading: IconBadge(
            icon: aiOk ? Icons.check_circle : Icons.warning_amber_outlined,
            color: aiOk
                ? AppSemanticColors.resolve(AppSemanticColors.success, b)
                : AppSemanticColors.resolve(AppSemanticColors.warning, b),
            size: 34,
            iconSize: 17,
            filled: false,
          ),
          title: aiOk ? 'Groq API configured' : 'No Groq API key configured',
          subtitle: aiOk
              ? '${data.aiModel} · ${data.aiQueriesToday} quer${data.aiQueriesToday == 1 ? 'y' : 'ies'} today'
              : 'AI Advisor is offline.',
          showDivider: true,
        ),
        DashRow(
          leading: IconBadge(
            icon: Icons.file_download_outlined,
            color: AppSemanticColors.resolve(AppSemanticColors.info, b),
            size: 34,
            iconSize: 17,
            filled: false,
          ),
          title: 'Export history',
          subtitle: data.lastExportAt != null
              ? '$exports report${exports == 1 ? '' : 's'} · Latest '
                  '${DateFormat('MMM d, h:mm a').format(data.lastExportAt!.toLocal())}'
              : 'No reports exported yet.',
          showDivider: true,
        ),
      ],
    );
  }

  Widget _buildNeedsAttentionCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = cs.brightness;
    final warning =
        AppSemanticColors.resolve(AppSemanticColors.warning, b);

    final items = <_AttentionItem>[];
    if (data.trashCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.delete_outline,
        title:
            'Trash contains deleted ${data.trashCount == 1 ? 'item' : 'items'}',
        subtitle:
            '${data.trashCount} item${data.trashCount == 1 ? '' : 's'} · review for permanent deletion',
      ));
    }
    if (data.inactiveUsers > 0) {
      items.add(_AttentionItem(
        icon: Icons.person_off_outlined,
        title: '${data.inactiveUsers} inactive '
            '${data.inactiveUsers == 1 ? 'user' : 'users'}',
        subtitle: 'review for reactivation or deletion',
      ));
    }

    final count = items.length;

    return DashCard(
      title: 'Needs Attention',
      icon: Icons.warning_amber_outlined,
      iconAccent: DashAccent.amber,
      alert: count > 0,
      trailing: count > 0
          ? StatusPill(
              label: '$count',
              color: warning,
            )
          : null,
      children: count > 0
          ? List<Widget>.generate(items.length, (i) {
              return DashRow(
                leading: IconBadge(
                  icon: items[i].icon,
                  color: warning,
                  size: 34,
                  iconSize: 17,
                  filled: false,
                ),
                title: items[i].title,
                subtitle: items[i].subtitle,
                showDivider: i > 0,
              );
            })
          : [
              DashRow(
                leading: IconBadge(
                  icon: Icons.check_circle,
                  color: AppSemanticColors.resolve(
                      AppSemanticColors.success, b),
                  size: 34,
                  iconSize: 17,
                  filled: false,
                ),
                title: 'Nothing needs attention',
                showDivider: false,
              ),
            ],
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return DashCard(
      title: 'Recent System Activity',
      children: activities.isEmpty
          ? const [Text('No activity yet.')]
          : _activityRows(context, activities),
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
    final filter = ref.watch(salesPeriodFilterProvider);
    final authNotifier = ref.read(authStateProvider.notifier);

    final changePct =
        analytics.comparison.totalChangePercent(analytics.totalSales);
    final sparkValues =
        analytics.trend.map((p) => p.total).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroKpiCard(
          icon: Icons.payments_outlined,
          label: 'My Sales · ${_trendPillLabel(filter)}',
          amount: CurrencyUtils.format(analytics.totalSales),
          deltaPercent: changePct,
          deltaSuffix: _deltaSuffix(filter),
          sparkValues: sparkValues,
          footStats: [
            HeroFootStat('${analytics.transactionCount}', 'sales'),
            HeroFootStat('${analytics.itemsSold}', 'items'),
            HeroFootStat(
              CurrencyUtils.formatWhole(analytics.averageTransaction),
              'avg',
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        if (authNotifier.hasPermission('create_sales'))
          BigCtaButton(
            icon: Icons.point_of_sale,
            label: 'New Sale',
            onTap: () => RouteGuard.pushIfAuthorized(
              context, ref,
              screen: const POSScreen(),
              permission: 'create_sales',
              routeName: 'pos_new_sale',
            ),
          ),
        if (authNotifier.hasPermission('create_sales'))
          const SizedBox(height: Spacing.lg),
        _buildQuickActionsCard(context, ref, authNotifier),
        const SizedBox(height: Spacing.lg),
        _buildStaffSalesTrendCard(context, analytics, filter),
        const SizedBox(height: Spacing.lg),
        _buildTopProductsCard(context, analytics),
        const SizedBox(height: Spacing.lg),
        _buildPaymentBreakdownCard(context, analytics),
        const SizedBox(height: Spacing.lg),
        _buildInventoryCard(context),
        const SizedBox(height: Spacing.lg),
        _buildLowStockCard(
          context,
          ref,
          data.lowStockProducts,
          data.categoryNames,
        ),
        const SizedBox(height: Spacing.lg),
        _buildRecentActivityCard(context, data.recentActivities),
      ],
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    WidgetRef ref,
    AuthStateNotifier authNotifier,
  ) {
    final children = <Widget>[
      if (authNotifier.hasPermission('add_stock'))
        QuickActionTile(
          icon: Icons.warehouse_outlined,
          label: 'Add Stock',
          accent: DashAccent.amber,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const StockScreen(),
            permission: 'add_stock',
            routeName: 'stock',
          ),
        ),
      if (authNotifier.hasPermission('view_sales'))
        QuickActionTile(
          icon: Icons.receipt_long,
          label: 'My Sales',
          accent: DashAccent.blue,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const SalesScreen(),
            permission: 'view_sales',
            routeName: 'sales',
          ),
        ),
      if (authNotifier.hasPermission('view_reports'))
        QuickActionTile(
          icon: Icons.bar_chart,
          label: 'Reports',
          accent: DashAccent.deep,
          onTap: () => RouteGuard.pushIfAuthorized(
            context, ref,
            screen: const SalesAnalyticsScreen(),
            permission: 'view_reports',
            routeName: 'reports',
          ),
        ),
    ];
    return DashCard(
      title: '',
      children: [QuickActionPanel(columns: 4, children: children)],
    );
  }

  Widget _buildStaffSalesTrendCard(
    BuildContext context,
    SalesAnalytics analytics,
    SalesPeriodFilter filter,
  ) {
    if (analytics.trend.isEmpty || _trendIsAllZero(analytics.trend)) {
      return const DashCard(
        title: 'My Sales Trend',
        children: [Text('No sales recorded this period.')],
      );
    }
    final points = analytics.trend
        .map((p) => _toBarPoint(p, filter.period))
        .toList();
    final highlightIndex = _highlightIndex(points);
    return DashCard(
      title: 'My Sales Trend',
      children: [
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _buildTrendBars(context, points, highlightIndex,
                barWidth: 8),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _buildTrendLabels(context, points),
        ),
        const SizedBox(height: Spacing.xs),
        _buildTrendLegend(context),
      ],
    );
  }

  Widget _buildTopProductsCard(BuildContext context, SalesAnalytics analytics) {
    final products = analytics.topProducts;
    if (products.isEmpty) {
      return const DashCard(
        title: 'My Top Products',
        children: [Text('No products sold this period.')],
      );
    }

    return DashCard(
      title: 'My Top Products',
      children: _topProductRows(context, products),
    );
  }

  Widget _buildPaymentBreakdownCard(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    final breakdown = analytics.paymentBreakdown;
    if (breakdown.isEmpty) {
      return const DashCard(
        title: 'Payment Breakdown',
        children: [Text('No payment data this period.')],
      );
    }

    return DashCard(
      title: 'Payment Breakdown',
      children: _paymentBreakdownRows(context, breakdown),
    );
  }

  Widget _buildInventoryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = data.inventoryStatus;
    if (status.total == 0) {
      return const DashCard(
        title: 'Inventory Status',
        children: [Text('No products yet.')],
      );
    }

    return DashCard(
      title: 'Inventory Status',
      children: [
        DonutChart(
          size: 100,
          segments: [
            DonutSegment(
              label: 'Normal',
              value: status.normal,
              color: AppSemanticColors.resolve(
                  AppSemanticColors.success, cs.brightness),
            ),
            DonutSegment(
              label: 'Low Stock',
              value: status.lowStock,
              color: AppSemanticColors.resolve(
                  AppSemanticColors.warning, cs.brightness),
            ),
            DonutSegment(
              label: 'Out of Stock',
              value: status.outOfStock,
              color: AppSemanticColors.resolve(
                  AppSemanticColors.error, cs.brightness),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLowStockCard(
    BuildContext context,
    WidgetRef ref,
    List<Product> products,
    Map<int, String> categoryNames,
  ) {
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);

    return DashCard(
      title: 'Low Stock',
      alert: products.isNotEmpty,
      trailing: products.isNotEmpty
          ? StatusPill(
              label: '${products.length} items',
              color: AppSemanticColors.resolve(
                  AppSemanticColors.warning, cs.brightness),
            )
          : null,
      children: [
        if (products.isEmpty)
          Row(
            children: [
              IconBadge(
                icon: Icons.check_circle,
                color: AppSemanticColors.resolve(
                    AppSemanticColors.success, cs.brightness),
                size: 32,
                iconSize: 15,
                filled: false,
              ),
              const SizedBox(width: Spacing.md),
              const Text('Inventory is healthy'),
            ],
          )
        else
          ..._lowStockRows(context, products, categoryNames),
        if (products.isNotEmpty && authNotifier.hasPermission('add_stock'))
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: InkWell(
                onTap: () => RouteGuard.pushIfAuthorized(
                  context, ref,
                  screen: const StockScreen(),
                  permission: 'add_stock',
                  routeName: 'stock',
                ),
                child: Text(
                  'View Stock →',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: AppSemanticColors.resolve(
                      AppSemanticColors.info,
                      cs.brightness,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentActivityCard(
    BuildContext context,
    List<ActivityLog> activities,
  ) {
    return DashCard(
      title: 'My Recent Activity',
      children: activities.isEmpty
          ? const [Text('No activity yet.')]
          : _activityRows(context, activities),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared pieces
// ─────────────────────────────────────────────────────────────────────────

class _TrendPill extends StatelessWidget {
  final SalesPeriodFilter filter;

  const _TrendPill({required this.filter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dashAccentTint(cs.primary),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _trendPillLabel(filter),
        style: AppTypography.labelSmall(context).copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AttentionItem {
  final IconData icon;
  final String title;
  final String subtitle;

  _AttentionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _BarPoint {
  final String label;
  final double value;

  _BarPoint({required this.label, required this.value});
}

// ─────────────────────────────────────────────────────────────────────────
// Row helpers
// ─────────────────────────────────────────────────────────────────────────

List<Widget> _paymentRows(
  BuildContext context,
  List<PaymentBreakdown> breakdown,
  double total,
) {
  return List<Widget>.generate(breakdown.length, (i) {
    final item = breakdown[i];
    final percent = item.percentageOf(total);
    final (icon, accent) = _paymentIconAccent(item.method);
    return PaymentProgressRow(
      icon: icon,
      accent: accent,
      method: item.method,
      amount: CurrencyUtils.formatWhole(item.total),
      percent: percent,
      showDivider: i > 0,
    );
  });
}

List<Widget> _paymentBreakdownRows(
  BuildContext context,
  List<PaymentBreakdown> breakdown,
) {
  return List<Widget>.generate(breakdown.length, (i) {
    final item = breakdown[i];
    final (icon, accent) = _paymentIconAccent(item.method);
    final color = dashAccentColor(context, accent);
    return DashRow(
      leading: IconBadge(
        icon: icon,
        color: color,
        size: 34,
        iconSize: 17,
        filled: false,
      ),
      title: item.method,
      subtitle:
          '${item.count} transaction${item.count == 1 ? '' : 's'}',
      showDivider: i > 0,
      trailing: DashRowEnd(amount: CurrencyUtils.formatWhole(item.total)),
    );
  });
}

List<Widget> _topProductRows(
  BuildContext context,
  List<TopProductResult> products,
) {
  final b = Theme.of(context).brightness;
  return List<Widget>.generate(products.length, (i) {
    final p = products[i];
    return DashRow(
      leading: DashThumb(label: p.productName),
      title: p.productName,
      subtitle:
          '${p.categoryName ?? 'Product'} · ${p.totalQuantity} sold',
      showDivider: i > 0,
      trailing: DashRowEnd(
        amount: CurrencyUtils.formatWhole(p.revenue),
        pill: _rankPill(i + 1, b),
      ),
    );
  });
}

List<Widget> _staffRows(
  BuildContext context,
  List<StaffSalesSummary> summaries,
  List<Sale> sales,
) {
  return List<Widget>.generate(summaries.length, (i) {
    return _StaffRow(
      index: i,
      summary: summaries[i],
      sales: sales,
      showDivider: i > 0,
    );
  });
}

List<Widget> _saleRows(BuildContext context, List<Sale> sales) {
  return List<Widget>.generate(sales.length, (i) {
    return _SaleRow(sale: sales[i], showDivider: i > 0);
  });
}

List<Widget> _activityRows(BuildContext context, List<ActivityLog> activities) {
  return List<Widget>.generate(activities.length, (i) {
    return _ActivityRow(activity: activities[i], showDivider: i > 0);
  });
}

List<Widget> _lowStockRows(
  BuildContext context,
  List<Product> products,
  Map<int, String> categoryNames,
) {
  return List<Widget>.generate(products.length, (i) {
    return _LowStockRow(
      product: products[i],
      categoryName: categoryNames[products[i].categoryId],
      showDivider: i > 0,
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Concrete row widgets
// ─────────────────────────────────────────────────────────────────────────

class _StaffRow extends StatelessWidget {
  final int index;
  final StaffSalesSummary summary;
  final List<Sale> sales;
  final bool showDivider;

  const _StaffRow({
    required this.index,
    required this.summary,
    required this.sales,
    this.showDivider = true,
  });

  String _firstSaleTime() {
    final times = sales
        .where((s) => s.userId == summary.userId)
        .map((s) => s.createdAt)
        .toList();
    if (times.isEmpty) return '';
    times.sort();
    return _formatShortTime(times.first);
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final colors = [
      AppSemanticColors.primary,
      AppSemanticColors.teal,
      AppSemanticColors.violet,
      AppSemanticColors.warning,
    ];
    final bgColor = AppSemanticColors.resolve(colors[index % colors.length], b);
    final delta = _staffDelta(summary);

    Widget? pill;
    if (delta != null) {
      pill = StatusPill(
        label: '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
        color: delta >= 0
            ? AppSemanticColors.resolve(AppSemanticColors.success, b)
            : AppSemanticColors.resolve(AppSemanticColors.warning, b),
        icon: delta >= 0 ? Icons.trending_up : Icons.trending_down,
      );
    }

    final firstSale = _firstSaleTime();
    final subtitle = firstSale.isNotEmpty
        ? '${summary.transactionCount} sales · $firstSale'
        : '${summary.transactionCount} sales';

    return DashRow(
      leading: DashAvatar(name: summary.fullName, color: bgColor),
      title: summary.fullName,
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: DashRowEnd(
        amount: CurrencyUtils.formatWhole(summary.totalSales),
        pill: pill,
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  final Product product;
  final String? categoryName;
  final bool showDivider;

  const _LowStockRow({
    required this.product,
    this.categoryName,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final warning = AppSemanticColors.resolve(
        AppSemanticColors.warning, Theme.of(context).brightness);
    return DashRow(
      leading: DashThumb(label: product.name),
      title: product.name,
      subtitle: categoryName,
      showDivider: showDivider,
      trailing: Text(
        '${product.stock} left',
        style: AppTypography.titleSmallBold(context).copyWith(color: warning),
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final bool showDivider;

  const _SaleRow({required this.sale, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final customer = sale.customerName?.isNotEmpty == true
        ? sale.customerName!
        : 'Walk-in';
    final time = _formatShortTime(sale.createdAt);
    final subtitle = '$customer · ${sale.paymentMethod} · $time';

    Color pillColor;
    String pillLabel;
    if (sale.isConfirmed) {
      pillColor =
          AppSemanticColors.resolve(AppSemanticColors.success, cs.brightness);
      pillLabel = 'Paid';
    } else if (sale.isPending) {
      pillColor =
          AppSemanticColors.resolve(AppSemanticColors.warning, cs.brightness);
      pillLabel = 'Pending';
    } else {
      pillColor =
          AppSemanticColors.resolve(AppSemanticColors.error, cs.brightness);
      pillLabel = 'Cancelled';
    }

    return DashRow(
      leading: IconBadge(
        icon: Icons.receipt_long,
        color: AppSemanticColors.resolve(AppSemanticColors.info, cs.brightness),
        square: true,
        size: 32,
        iconSize: 15,
        filled: false,
      ),
      title: '#${sale.receiptNumber ?? sale.id}',
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: DashRowEnd(
        amount: CurrencyUtils.format(sale.totalAmount),
        pill: StatusPill(label: pillLabel, color: pillColor),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityLog activity;
  final bool showDivider;

  const _ActivityRow({required this.activity, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDetails = activity.details?.isNotEmpty == true;
    final subtitle = hasDetails
        ? '${activity.details} · ${_formatShortTime(activity.createdAt)}'
        : _formatDateTime(activity.createdAt);

    return DashRow(
      leading: IconBadge(
        icon: Icons.history,
        color: cs.onSurfaceVariant,
        square: true,
        size: 32,
        iconSize: 15,
        filled: false,
      ),
      title: _humanizeAction(activity.action),
      subtitle: subtitle,
      showDivider: showDivider,
    );
  }
}

class _MockupBar extends StatelessWidget {
  final double value;
  final double maxValue;
  final bool isHot;
  final double? width;

  const _MockupBar({
    required this.value,
    required this.maxValue,
    this.isHot = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final cs = Theme.of(context).colorScheme;
    final ratio =
        maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Container(
          width: width ?? double.infinity,
          height: h * ratio,
          decoration: BoxDecoration(
            color: isHot
                ? cs.primary
                : AppSemanticColors.resolve(
                    AppSemanticColors.primaryLight,
                    b,
                  ).withValues(alpha: 0.25),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Trend chart helpers (shared by Owner and Staff)
// ─────────────────────────────────────────────────────────────────────────

List<Widget> _buildTrendBars(
  BuildContext context,
  List<_BarPoint> points,
  int highlightIndex, {
  double? barWidth,
}) {
  if (points.isEmpty) return const [];
  final maxValue =
      points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
  return List<Widget>.generate(points.length, (i) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: _MockupBar(
          value: points[i].value,
          maxValue: maxValue,
          isHot: i == highlightIndex,
          width: barWidth,
        ),
      ),
    );
  });
}

List<Widget> _buildTrendLabels(BuildContext context, List<_BarPoint> points) {
  final count = points.length;
  if (count <= 1) return const [];
  // Show all labels for short series (weekly/monthly), sample for long ones.
  final step = count <= 7 ? 1 : math.max(1, (count / 6).ceil());
  final cs = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
      );

  final children = <Widget>[];
  for (var i = 0; i < count; i += step) {
    final label = Text(
      points[i].label,
      textAlign: TextAlign.center,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    children.add(step == 1 ? Expanded(child: label) : label);
  }

  if (step > 1 &&
      children.isNotEmpty &&
      (children.last as Text).data != points.last.label) {
    children.add(Text(points.last.label, style: style));
  }

  return children;
}

// ─────────────────────────────────────────────────────────────────────────
// Global helpers
// ─────────────────────────────────────────────────────────────────────────

String _trendPillLabel(SalesPeriodFilter filter) {
  final today = startOfDay(DateTime.now());
  return switch (filter.period) {
    SalesPeriod.daily =>
      filter.selectedDate == today ? 'Today' : 'Daily',
    SalesPeriod.weekly => 'This Week',
    SalesPeriod.monthly => 'This Month',
    SalesPeriod.custom => 'Custom',
  };
}

String _deltaSuffix(SalesPeriodFilter filter) {
  return switch (filter.period) {
    SalesPeriod.daily => 'vs yesterday',
    SalesPeriod.weekly => 'vs last week',
    SalesPeriod.monthly => 'vs last month',
    SalesPeriod.custom => 'vs previous period',
  };
}

(IconData, DashAccent) _paymentIconAccent(String method) {
  final m = method.toLowerCase();
  if (m == 'cash') {
    return (Icons.payments_outlined, DashAccent.blue);
  }
  if (m.contains('gcash')) {
    return (Icons.qr_code, DashAccent.teal);
  }
  if (m.contains('maya') || m.contains('paymaya')) {
    return (Icons.qr_code_2, DashAccent.purple);
  }
  return (Icons.account_balance_wallet_outlined, DashAccent.grey);
}

Widget _rankPill(int rank, Brightness b) {
  final color = switch (rank) {
    1 => AppSemanticColors.resolve(AppSemanticColors.success, b),
    2 => AppSemanticColors.resolve(AppSemanticColors.info, b),
    _ => AppSemanticColors.resolve(AppSemanticColors.neutral, b),
  };
  return StatusPill(label: '#$rank', color: color);
}

String _formatDateTime(DateTime dt) {
  return DateFormat('MMM d, y \u00b7 h:mm a').format(dt.toLocal());
}

String _formatShortTime(DateTime dt) {
  return DateFormat('h:mm a').format(dt.toLocal());
}

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

double? _staffDelta(StaffSalesSummary summary) {
  final prev = summary.previousTotalSales ?? 0.0;
  final curr = summary.totalSales;
  if (prev == 0.0) return curr == 0.0 ? null : 100.0;
  return ((curr - prev) / prev) * 100;
}

bool _trendIsAllZero(List<DailySalesPoint> trend) {
  for (final p in trend) {
    if (p.total != 0.0 || p.count != 0) return false;
  }
  return true;
}

_BarPoint _toBarPoint(DailySalesPoint point, SalesPeriod period) {
  return _BarPoint(label: _barLabel(point.date, period), value: point.total);
}

int _highlightIndex(List<_BarPoint> points) {
  if (points.isEmpty) return -1;
  var maxIndex = 0;
  for (var i = 1; i < points.length; i++) {
    if (points[i].value > points[maxIndex].value) maxIndex = i;
  }
  return maxIndex;
}

String _barLabel(DateTime date, SalesPeriod period) {
  switch (period) {
    case SalesPeriod.weekly:
      const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return names[date.weekday % 7];
    case SalesPeriod.monthly:
      final week = ((date.day - 1) / 7).floor() + 1;
      return 'Week $week';
    case SalesPeriod.daily:
    case SalesPeriod.custom:
      return '${date.month}/${date.day}';
  }
}

Widget _buildTrendLegend(BuildContext context) {
  final b = Theme.of(context).brightness;
  final cs = Theme.of(context).colorScheme;
  return TrendChartLegend(
    normalColor: AppSemanticColors.resolve(AppSemanticColors.primaryLight, b),
    highlightColor: cs.primary,
  );
}
