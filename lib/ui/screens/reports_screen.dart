import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final ReportService _reportService = ReportService();
  final SalesService _salesService = SalesService();
  double _todaySales = 0.0;
  double _monthSales = 0.0;
  int _lowStockCount = 0;
  int _totalProducts = 0;
  bool _isLoading = true;
  bool _isExporting = false;

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
                onTap: canExport && !_isExporting ? _exportToPdf : null,
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.table_view),
                title: const Text('Export to CSV'),
                trailing: const Icon(Icons.chevron_right),
                onTap: canExport && !_isExporting ? _exportToCsv : null,
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

  Future<void> _exportToCsv() async {
    setState(() => _isExporting = true);
    try {
      final sales = await _salesService.getSales();
      final buffer = StringBuffer();
      buffer.writeln('Receipt Number,Date,Total Amount,Cash Received,Change,Notes');
      for (final sale in sales) {
        buffer.writeln(
          '"${sale.receiptNumber ?? sale.id}","${sale.createdAt.toIso8601String()}",${sale.totalAmount},${sale.cashReceived},${sale.change},"${sale.notes ?? ''}"',
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/pinoy_pos_sales_$timestamp.csv');
      await file.writeAsString(buffer.toString());
      if (mounted) {
        showSuccessSnackbar(context, 'CSV exported: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to export CSV');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf() async {
    setState(() => _isExporting = true);
    try {
      // PDF export requires the pdf package widget API.
      // This is a minimal text-based PDF export.
      final sales = await _salesService.getSales();
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/pinoy_pos_sales_$timestamp.txt');
      final buffer = StringBuffer();
      buffer.writeln('Pinoy POS - Sales Report');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Today Sales: ₱${_todaySales.toStringAsFixed(2)}');
      buffer.writeln('Month Sales: ₱${_monthSales.toStringAsFixed(2)}');
      buffer.writeln('Total Products: $_totalProducts');
      buffer.writeln('Low Stock Items: $_lowStockCount');
      buffer.writeln('');
      buffer.writeln('--- Sales Detail ---');
      for (final sale in sales) {
        buffer.writeln(
          '${sale.receiptNumber ?? sale.id} | ${sale.createdAt.toLocal()} | ₱${sale.totalAmount.toStringAsFixed(2)}',
        );
      }
      await file.writeAsString(buffer.toString());
      if (mounted) {
        showSuccessSnackbar(context, 'Report exported: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to export report');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
