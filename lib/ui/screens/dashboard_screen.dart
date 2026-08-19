import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/dashboard_provider.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/donut_chart.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/kpi_card.dart';
import 'package:pinoy_pos/ui/widgets/mini_bar_chart.dart';

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
      appBar: AppHeader(
        title: 'Dashboard',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(dashboardProvider.notifier).load(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).load(),
        child: switch (dashboardState) {
          DashboardLoading() => _DashboardLoadingView(user: user),
          DashboardError(:final message) => ErrorState(
              title: 'Unable to Load Dashboard',
              message: message,
              onRetry: () => ref.read(dashboardProvider.notifier).load(),
            ),
          DashboardLoaded(:final owner, :final admin, :final staff) =>
            _DashboardLoadedView(
              user: user,
              owner: owner,
              admin: admin,
              staff: staff,
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
  final OwnerDashboardData? owner;
  final AdminDashboardData? admin;
  final StaffDashboardData? staff;

  const _DashboardLoadedView({
    this.user,
    this.owner,
    this.admin,
    this.staff,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return const Center(child: Text('Not authenticated'));
    }

    final role = user!.role;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeHeader(user: user!),
          const SizedBox(height: Spacing.xl),
          switch (role) {
            UserRole.owner => _OwnerDashboard(data: owner!),
            UserRole.admin => _AdminDashboard(data: admin!),
            UserRole.staff => _StaffDashboard(data: staff!),
          },
        ],
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
                style: Theme.of(context).textTheme.headlineSmall,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

/// Section title with consistent spacing.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// Formats a currency value in PHP.
String _peso(double value) => '₱${value.toStringAsFixed(2)}';

/// Formats a DateTime for compact recent-activity display.
String _formatDateTime(DateTime dt) {
  return DateFormat('MMM d · h:mm a').format(dt.toLocal());
}

/// Formats a day label for the sales trend chart (e.g. "Mon").
String _dayLabel(DateTime dt) => DateFormat('E').format(dt);

// ─────────────────────────────────────────────────────────────────────────
// Owner Dashboard
// ─────────────────────────────────────────────────────────────────────────

class _OwnerDashboard extends ConsumerWidget {
  final OwnerDashboardData data;
  const _OwnerDashboard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary KPIs ──
        KpiGrid(
          children: [
            KpiCard(
              label: "Today's Sales",
              value: _peso(data.todaySales),
              icon: Icons.payments_outlined,
              iconColor: cs.primary,
              subtitle: '${data.todayTransactions} transactions',
              tier: KpiCardTier.primary,
            ),
            KpiCard(
              label: 'Transactions',
              value: '${data.todayTransactions}',
              icon: Icons.receipt_long_outlined,
              iconColor: cs.tertiary,
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Low Stock',
              value: '${data.lowStockCount}',
              icon: Icons.warning_amber,
              iconColor: AppSemanticColors.warning,
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Out of Stock',
              value: '${data.outOfStockCount}',
              icon: Icons.error_outline,
              iconColor: AppSemanticColors.error,
              tier: KpiCardTier.secondary,
            ),
          ],
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Sales trend chart ──
        _buildSalesTrendCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Two-column area on tablet/desktop: top products + inventory ──
        _ResponsiveTwoColumn(
          left: _buildTopProductsCard(context),
          right: _buildInventoryCard(context),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Low stock alert ──
        _buildLowStockAlert(context, data.lowStockProducts, authNotifier),
        const SizedBox(height: Spacing.xxl),

        // ── Recent sales ──
        _buildRecentSalesCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Announcements ──
        if (data.announcements.isNotEmpty) ...[
          _buildAnnouncementsCard(context),
          const SizedBox(height: Spacing.xxl),
        ],

        // ── Recent activity ──
        _buildRecentActivityCard(context, data.recentActivities),
        const SizedBox(height: Spacing.xxl),

        // ── AI Advisor entry ──
        if (authNotifier.hasPermission('view_ai_advisor')) ...[
          _buildAIAdvisorCard(context),
          const SizedBox(height: Spacing.xxl),
        ],

        // ── Quick actions ──
        _buildOwnerQuickActions(context, ref, authNotifier),
      ],
    );
  }

  Widget _buildSalesTrendCard(BuildContext context) {
    final hasData = data.salesTrend.any((p) => p.total > 0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Sales (Last 7 Days)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          if (hasData)
            MiniBarChart(
              points: data.salesTrend
                  .map((p) => BarChartPoint(
                        label: _dayLabel(p.date),
                        value: p.total,
                      ))
                  .toList(),
              valuePrefix: '₱',
            )
          else
            const _ChartEmptyState(message: 'No sales data available yet.'),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Top Products',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (data.topProducts.isEmpty)
            const _ChartEmptyState(message: 'No sales recorded yet.')
          else
            Column(
              children: data.topProducts.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return _RankedListTile(
                  rank: i + 1,
                  title: p.name,
                  trailing: '${p.totalQuantity} sold',
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInventoryCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Inventory Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          if (data.inventoryStatus.total == 0)
            const _ChartEmptyState(message: 'No products yet.')
          else
            DonutChart(
              segments: [
                DonutSegment(
                  label: 'Normal',
                  value: data.inventoryStatus.normal,
                  color: AppSemanticColors.success,
                ),
                DonutSegment(
                  label: 'Low Stock',
                  value: data.inventoryStatus.lowStock,
                  color: AppSemanticColors.warning,
                ),
                DonutSegment(
                  label: 'Out of Stock',
                  value: data.inventoryStatus.outOfStock,
                  color: AppSemanticColors.error,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(
      BuildContext context, List<dynamic> products, dynamic authNotifier) {
    if (products.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppSemanticColors.success),
            const SizedBox(width: Spacing.md),
            const Expanded(child: Text('Inventory is healthy')),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: AppSemanticColors.warning),
              const SizedBox(width: Spacing.sm),
              Text('Low Stock Alert',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ...products.take(5).map((p) => _LowStockTile(
                name: (p as dynamic).name as String,
                remaining: (p as dynamic).stock as int,
              )),
          if (authNotifier.hasPermission('add_stock')) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockScreen()),
                ),
                icon: const Icon(Icons.warehouse_outlined),
                label: const Text('View Stock'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSalesCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Recent Sales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (data.recentSales.isEmpty)
            const _ChartEmptyState(message: 'No sales recorded yet.')
          else
            Column(
              children: data.recentSales.map((s) => _RecentSaleTile(
                    receipt: '#${s.receiptNumber ?? s.id}',
                    amount: _peso(s.totalAmount),
                    time: _formatDateTime(s.createdAt),
                  )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Announcements',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ...data.announcements.take(3).map((a) => _AnnouncementTile(
                title: a.title,
                content: a.content,
                isPinned: a.isPinned,
              )),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(BuildContext context, List<dynamic> activities) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (activities.isEmpty)
            const _ChartEmptyState(message: 'No activity yet.')
          else
            Column(
              children: activities.take(5).map((a) {
                final log = a as dynamic;
                return _ActivityTile(
                  action: _humanizeAction(log.action as String),
                  details: log.details as String?,
                  time: _formatDateTime(log.createdAt as DateTime),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAIAdvisorCard(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AIAdvisorScreen()),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.tertiary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Business Advisor',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                Text('Analyze your latest sales and inventory.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _buildOwnerQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Quick Actions'),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            if (authNotifier.hasPermission('create_sales'))
              _QuickAction(
                label: 'New Sale',
                icon: Icons.point_of_sale,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const POSScreen()),
                ),
              ),
            if (authNotifier.hasPermission('edit_products'))
              _QuickAction(
                label: 'Add Product',
                icon: Icons.add_box_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductsScreen()),
                ),
              ),
            if (authNotifier.hasPermission('add_stock'))
              _QuickAction(
                label: 'Add Stock',
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
                icon: Icons.receipt_long,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesScreen()),
                ),
              ),
            if (authNotifier.hasPermission('view_reports'))
              _QuickAction(
                label: 'Reports',
                icon: Icons.analytics_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
            if (authNotifier.hasPermission('view_ai_advisor'))
              _QuickAction(
                label: 'AI Advisor',
                icon: Icons.auto_awesome,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AIAdvisorScreen()),
                ),
              ),
          ],
        ),
      ],
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
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary KPIs ──
        KpiGrid(
          children: [
            KpiCard(
              label: 'Active Users',
              value: '${data.activeUsers}',
              icon: Icons.person_outline,
              iconColor: AppSemanticColors.success,
              tier: KpiCardTier.primary,
            ),
            KpiCard(
              label: 'Inactive Users',
              value: '${data.inactiveUsers}',
              icon: Icons.person_off_outlined,
              iconColor: cs.onSurfaceVariant,
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Recent Activity',
              value: '${data.recentActivityCount}',
              icon: Icons.history,
              iconColor: cs.tertiary,
              subtitle: 'last 7 days',
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Trash Items',
              value: '${data.trashCount}',
              icon: Icons.delete_outline,
              iconColor: AppSemanticColors.warning,
              tier: KpiCardTier.secondary,
            ),
          ],
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Two-column: user distribution + backup status ──
        _ResponsiveTwoColumn(
          left: _buildUserDistributionCard(context),
          right: _buildBackupCard(context),
        ),
        const SizedBox(height: Spacing.xxl),

        // ── Recent activity ──
        _buildRecentActivityCard(context, data.recentActivities),
        const SizedBox(height: Spacing.xxl),

        // ── Quick actions ──
        _buildAdminQuickActions(context, ref, authNotifier),
      ],
    );
  }

  Widget _buildUserDistributionCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Users by Role',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.lg),
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
                  color: AppSemanticColors.info,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBackupCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.backup_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Backup Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (data.backupStatus.hasBackup && data.backupStatus.lastBackupDate != null)
            Row(
              children: [
                Icon(Icons.check_circle, color: AppSemanticColors.success),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Latest: ${DateFormat('MMM d, y · h:mm a').format(data.backupStatus.lastBackupDate!.toLocal())}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                const SizedBox(width: Spacing.sm),
                const Expanded(child: Text('No backup has been created yet.')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(BuildContext context, List<dynamic> activities) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Recent System Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (activities.isEmpty)
            const _ChartEmptyState(message: 'No activity yet.')
          else
            Column(
              children: activities.take(5).map((a) {
                final log = a as dynamic;
                return _ActivityTile(
                  action: _humanizeAction(log.action as String),
                  details: log.details as String?,
                  time: _formatDateTime(log.createdAt as DateTime),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAdminQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Quick Actions'),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            if (authNotifier.hasPermission('manage_users'))
              _QuickAction(
                label: 'Manage Users',
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
                icon: Icons.history,
                onTap: () => RouteGuard.pushIfAuthorized(
                  context, ref,
                  screen: const ActivityLogsScreen(),
                  permission: 'view_activity_logs',
                  routeName: 'activity_logs',
                ),
              ),
            if (authNotifier.hasPermission('view_settings'))
              _QuickAction(
                label: 'Settings',
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
      ],
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
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Primary KPIs (own sales only) ──
        KpiGrid(
          children: [
            KpiCard(
              label: 'My Sales Today',
              value: _peso(data.mySalesToday),
              icon: Icons.payments_outlined,
              iconColor: cs.primary,
              subtitle: '${data.myTransactionsToday} transactions',
              tier: KpiCardTier.primary,
            ),
            KpiCard(
              label: 'My Transactions',
              value: '${data.myTransactionsToday}',
              icon: Icons.receipt_long_outlined,
              iconColor: cs.tertiary,
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Low Stock',
              value: '${data.lowStockCount}',
              icon: Icons.warning_amber,
              iconColor: AppSemanticColors.warning,
              tier: KpiCardTier.secondary,
            ),
            KpiCard(
              label: 'Out of Stock',
              value: '${data.outOfStockCount}',
              icon: Icons.error_outline,
              iconColor: AppSemanticColors.error,
              tier: KpiCardTier.secondary,
            ),
          ],
        ),
        const SizedBox(height: Spacing.xxl),

        // ── My sales trend ──
        _buildMySalesTrendCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Inventory status ──
        _buildInventoryCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Low stock alert ──
        _buildLowStockAlert(context, ref, data.lowStockProducts, authNotifier),
        const SizedBox(height: Spacing.xxl),

        // ── My recent sales ──
        _buildMyRecentSalesCard(context),
        const SizedBox(height: Spacing.xxl),

        // ── Recent activity (own) ──
        _buildRecentActivityCard(context, data.recentActivities),
        const SizedBox(height: Spacing.xxl),

        // ── Quick actions ──
        _buildStaffQuickActions(context, ref, authNotifier),
      ],
    );
  }

  Widget _buildMySalesTrendCard(BuildContext context) {
    final hasData = data.mySalesTrend.any((p) => p.total > 0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('My Sales (Last 7 Days)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          if (hasData)
            MiniBarChart(
              points: data.mySalesTrend
                  .map((p) => BarChartPoint(
                        label: _dayLabel(p.date),
                        value: p.total,
                      ))
                  .toList(),
              valuePrefix: '₱',
            )
          else
            const _ChartEmptyState(message: 'No sales data available yet.'),
        ],
      ),
    );
  }

  Widget _buildInventoryCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Inventory Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          if (data.inventoryStatus.total == 0)
            const _ChartEmptyState(message: 'No products yet.')
          else
            DonutChart(
              segments: [
                DonutSegment(
                  label: 'Normal',
                  value: data.inventoryStatus.normal,
                  color: AppSemanticColors.success,
                ),
                DonutSegment(
                  label: 'Low Stock',
                  value: data.inventoryStatus.lowStock,
                  color: AppSemanticColors.warning,
                ),
                DonutSegment(
                  label: 'Out of Stock',
                  value: data.inventoryStatus.outOfStock,
                  color: AppSemanticColors.error,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(
      BuildContext context, WidgetRef ref, List<dynamic> products, dynamic authNotifier) {
    if (products.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppSemanticColors.success),
            const SizedBox(width: Spacing.md),
            const Expanded(child: Text('Inventory is healthy')),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: AppSemanticColors.warning),
              const SizedBox(width: Spacing.sm),
              Text('Low Stock Alert',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ...products.take(5).map((p) => _LowStockTile(
                name: (p as dynamic).name as String,
                remaining: (p as dynamic).stock as int,
              )),
          if (authNotifier.hasPermission('add_stock')) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => RouteGuard.pushIfAuthorized(
                  context, ref,
                  screen: const StockScreen(),
                  permission: 'add_stock',
                  routeName: 'stock',
                ),
                icon: const Icon(Icons.warehouse_outlined),
                label: const Text('View Stock'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMyRecentSalesCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('My Recent Sales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (data.myRecentSales.isEmpty)
            const _ChartEmptyState(message: 'No sales recorded yet.')
          else
            Column(
              children: data.myRecentSales.map((s) => _RecentSaleTile(
                    receipt: '#${s.receiptNumber ?? s.id}',
                    amount: _peso(s.totalAmount),
                    time: _formatDateTime(s.createdAt),
                  )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(BuildContext context, List<dynamic> activities) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: Spacing.sm),
              Text('Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (activities.isEmpty)
            const _ChartEmptyState(message: 'No activity yet.')
          else
            Column(
              children: activities.take(5).map((a) {
                final log = a as dynamic;
                return _ActivityTile(
                  action: _humanizeAction(log.action as String),
                  details: log.details as String?,
                  time: _formatDateTime(log.createdAt as DateTime),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStaffQuickActions(
      BuildContext context, WidgetRef ref, dynamic authNotifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Quick Actions'),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            if (authNotifier.hasPermission('create_sales'))
              _QuickAction(
                label: 'New Sale',
                icon: Icons.point_of_sale,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const POSScreen()),
                ),
              ),
            if (authNotifier.hasPermission('add_stock'))
              _QuickAction(
                label: 'Add Stock',
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
                icon: Icons.receipt_long,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesScreen()),
                ),
              ),
            if (authNotifier.hasPermission('view_reports'))
              _QuickAction(
                label: 'Reports',
                icon: Icons.analytics_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
          ],
        ),
      ],
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

class _RankedListTile extends StatelessWidget {
  final int rank;
  final String title;
  final String trailing;

  const _RankedListTile({
    required this.rank,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            trailing,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
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
          Icon(Icons.circle, size: 8, color: AppSemanticColors.warning),
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
                  color: AppSemanticColors.warning,
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

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Ensure minimum 48x48 touch target via SizedBox + adequate padding.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.md),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.onPrimaryContainer),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
