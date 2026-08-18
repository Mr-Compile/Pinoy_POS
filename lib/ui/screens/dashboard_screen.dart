import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ReportService _reportService = ReportService();

  // Business metrics
  double _todaySales = 0.0;
  double _monthSales = 0.0;
  int _lowStockCount = 0;
  int _totalProducts = 0;

  // System metrics
  int _totalUsers = 0;
  int _activeUsers = 0;
  String? _lastBackupPath;
  DateTime? _lastBackupDate;

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final authState = ref.read(authStateProvider);
      final role = authState.user?.role;

      if (role == UserRole.owner || role == UserRole.staff) {
        _todaySales = await _reportService.getTodaySales();
        _monthSales = await _reportService.getMonthSales();
        _lowStockCount = await _reportService.getLowStockCount();
        _totalProducts = await _reportService.getTotalProducts();
      }

      if (role == UserRole.admin) {
        _totalUsers = await _reportService.getTotalUsers();
        _activeUsers = await _reportService.getActiveUsers();
        _lastBackupPath = await _reportService.getLastBackupPath();
        _lastBackupDate = await _reportService.getLastBackupDate();
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load dashboard statistics. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadStats,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: ErrorState(
          title: 'Failed to Load Dashboard',
          message: _loadError,
          onRetry: _loadStats,
        ),
      );
    }

    final role = user?.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user != null)
                Text(
                  'Welcome, ${user.fullName}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              const SizedBox(height: 8),
              if (user != null)
                Chip(
                  label: Text(user.role.displayName),
                  avatar: const Icon(Icons.badge),
                ),
              const SizedBox(height: 24),
              switch (role) {
                UserRole.owner => _buildOwnerDashboard(),
                UserRole.admin => _buildSystemAdminDashboard(),
                UserRole.staff => _buildStaffDashboard(),
                null => const SizedBox.shrink(),
              },
            ],
          ),
        ),
      ),
    );
  }

  // --- Owner Dashboard: Business metrics ---

  Widget _buildOwnerDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business Overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(
          [
            _StatData("Today's Sales", '₱${_todaySales.toStringAsFixed(2)}',
                Icons.attach_money, Theme.of(context).colorScheme.primary),
            _StatData('Month Sales', '₱${_monthSales.toStringAsFixed(2)}',
                Icons.calendar_month, Theme.of(context).colorScheme.tertiary),
            _StatData('Low Stock', '$_lowStockCount', Icons.warning,
                Theme.of(context).colorScheme.error),
            _StatData('Total Products', '$_totalProducts', Icons.inventory_2,
                Theme.of(context).colorScheme.secondary),
          ],
        ),
        const SizedBox(height: 24),
        _buildQuickActions(),
      ],
    );
  }

  // --- System Admin Dashboard: System metrics ---

  Widget _buildSystemAdminDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('System Overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(
          [
            _StatData('Total Users', '$_totalUsers', Icons.people,
                Theme.of(context).colorScheme.primary),
            _StatData('Active Users', '$_activeUsers', Icons.person,
                Theme.of(context).colorScheme.tertiary),
            _StatData(
                'Backup Status',
                _lastBackupPath != null ? 'Available' : 'None',
                Icons.backup,
                _lastBackupPath != null
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error),
            _StatData(
                'Last Backup',
                _lastBackupDate != null
                    ? _lastBackupDate!.toLocal().toString().split(' ')[0]
                    : 'Never',
                Icons.schedule,
                Theme.of(context).colorScheme.secondary),
          ],
        ),
        const SizedBox(height: 24),
        _buildSystemQuickActions(),
      ],
    );
  }

  // --- Staff Dashboard: Operational metrics ---

  Widget _buildStaffDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(
          [
            _StatData('My Sales Today', '₱${_todaySales.toStringAsFixed(2)}',
                Icons.point_of_sale, Theme.of(context).colorScheme.primary),
            _StatData('My Month Sales', '₱${_monthSales.toStringAsFixed(2)}',
                Icons.calendar_month, Theme.of(context).colorScheme.tertiary),
            _StatData('Low Stock Alerts', '$_lowStockCount', Icons.warning,
                Theme.of(context).colorScheme.error),
            _StatData('Total Products', '$_totalProducts', Icons.inventory_2,
                Theme.of(context).colorScheme.secondary),
          ],
        ),
        const SizedBox(height: 24),
        _buildStaffQuickActions(),
      ],
    );
  }

  Widget _buildStatsGrid(List<_StatData> stats) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 600 ? 4 : 2;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: screenWidth >= 600 ? 1.2 : 1.0,
      children: stats.map((s) => _buildStatCard(s)).toList(),
    );
  }

  Widget _buildStatCard(_StatData stat) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(stat.icon, color: stat.color, size: 32),
          const SizedBox(height: 8),
          Text(stat.title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              stat.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // --- Quick Actions ---

  Widget _buildQuickActions() {
    final authNotifier = ref.read(authStateProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (authNotifier.hasPermission('create_sales'))
              _buildActionButton('New Sale', Icons.point_of_sale, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const POSScreen()),
                );
              }),
            if (authNotifier.hasPermission('edit_products'))
              _buildActionButton('Add Product', Icons.add, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductsScreen()),
                );
              }),
            if (authNotifier.hasPermission('view_reports'))
              _buildActionButton('Reports', Icons.analytics, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _buildSystemQuickActions() {
    final authNotifier = ref.read(authStateProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (authNotifier.hasPermission('manage_users'))
              _buildActionButton('Add User', Icons.person_add, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsersScreen()),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _buildStaffQuickActions() {
    final authNotifier = ref.read(authStateProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (authNotifier.hasPermission('create_sales'))
              _buildActionButton('New Sale', Icons.point_of_sale, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const POSScreen()),
                );
              }),
            if (authNotifier.hasPermission('view_reports'))
              _buildActionButton('My Reports', Icons.analytics, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return AppCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _StatData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _StatData(this.title, this.value, this.icon, this.color);
}
