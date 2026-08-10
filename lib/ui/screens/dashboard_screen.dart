import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ReportService _reportService = ReportService();
  double _todaySales = 0.0;
  double _monthSales = 0.0;
  int _lowStockCount = 0;
  int _totalProducts = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
    });

    final todaySales = await _reportService.getTodaySales();
    final monthSales = await _reportService.getMonthSales();
    final lowStockCount = await _reportService.getLowStockCount();
    final totalProducts = await _reportService.getTotalProducts();

    if (mounted) {
      setState(() {
        _todaySales = todaySales;
        _monthSales = monthSales;
        _lowStockCount = lowStockCount;
        _totalProducts = totalProducts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user != null)
              Text(
                'Welcome, ${user.fullName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _buildStatCard(
          'Today\'s Sales',
          '₱${_todaySales.toStringAsFixed(2)}',
          Icons.attach_money,
          Colors.green,
        ),
        _buildStatCard(
          'Month Sales',
          '₱${_monthSales.toStringAsFixed(2)}',
          Icons.calendar_month,
          Colors.blue,
        ),
        _buildStatCard(
          'Low Stock',
          '$_lowStockCount',
          Icons.warning,
          Colors.orange,
        ),
        _buildStatCard(
          'Total Products',
          '$_totalProducts',
          Icons.inventory_2,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final authNotifier = ref.read(authStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (authNotifier.hasPermission('create_sales'))
              _buildActionButton(
                'New Sale',
                Icons.point_of_sale,
                () {
                  // Navigate to POS - would need to access parent navigation
                },
              ),
            if (authNotifier.hasPermission('edit_products'))
              _buildActionButton(
                'Add Product',
                Icons.add,
                () {
                  // Navigate to Products - would need to access parent navigation
                },
              ),
            if (authNotifier.hasPermission('manage_users'))
              _buildActionButton(
                'Add User',
                Icons.person_add,
                () {
                  // Navigate to Users - would need to access parent navigation
                },
              ),
            if (authNotifier.hasPermission('view_reports'))
              _buildActionButton(
                'Reports',
                Icons.bar_chart,
                () {
                  // Navigate to Reports - would need to access parent navigation
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return AppCard(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }
}
