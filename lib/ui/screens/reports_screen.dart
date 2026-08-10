import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
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
    final authNotifier = ref.read(authStateProvider.notifier);
    final canExport = authNotifier.hasPermission('export_reports');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
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
            Text(
              'Sales Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  _buildStatRow('Today\'s Sales', '₱${_todaySales.toStringAsFixed(2)}'),
                  const Divider(),
                  _buildStatRow('Month Sales', '₱${_monthSales.toStringAsFixed(2)}'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Inventory Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  _buildStatRow('Total Products', '$_totalProducts'),
                  const Divider(),
                  _buildStatRow('Low Stock Items', '$_lowStockCount'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Export',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Export to PDF'),
                trailing: const Icon(Icons.chevron_right),
                onTap: canExport ? () {} : null,
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.table_view),
                title: const Text('Export to CSV'),
                trailing: const Icon(Icons.chevron_right),
                onTap: canExport ? () {} : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
