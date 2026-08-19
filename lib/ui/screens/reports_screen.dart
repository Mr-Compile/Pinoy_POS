import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  double _todaySales = 0.0;
  double _monthSales = 0.0;
  int _lowStockCount = 0;
  int _totalProducts = 0;
  bool _isLoading = true;
  bool _isExporting = false;

  DateTime? _filterStart;
  DateTime? _filterEnd;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
    });

    final reportService = ref.read(reportServiceProvider);
    final todaySales = await reportService.getTodaySales();
    final monthSales = await reportService.getMonthSales();
    final lowStockCount = await reportService.getLowStockCount();
    final totalProducts = await reportService.getTotalProducts();

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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: _filterStart ?? DateTime(now.year, now.month, 1),
      end: _filterEnd ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
    );

    if (picked != null) {
      setState(() {
        _filterStart = picked.start;
        _filterEnd = picked.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
      });
    }
  }

  String get _filterLabel {
    if (_filterStart == null || _filterEnd == null) {
      return 'All sales';
    }
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(_filterStart!)} to ${fmt(_filterEnd!)}';
  }

  Future<List> _getSalesForExport() async {
    final salesService = ref.read(salesServiceProvider);
    if (_filterStart != null && _filterEnd != null) {
      return salesService.getSalesByDateRange(_filterStart!, _filterEnd!);
    }
    return salesService.getSales();
  }

  Future<void> _recordExport({
    required String fileFormat,
    required String filePath,
  }) async {
    // Record through the ReportService provider so the UI never accesses
    // the repository or session manager directly.
    await ref.read(reportServiceProvider).recordExport(
          fileFormat: fileFormat,
          filePath: filePath,
          dateRangeStart: _filterStart,
          dateRangeEnd: _filterEnd,
        );
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
                  _buildStatRow("Today's Sales", 'PHP ${_todaySales.toStringAsFixed(2)}'),
                  const Divider(),
                  _buildStatRow('Month Sales', 'PHP ${_monthSales.toStringAsFixed(2)}'),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.date_range),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Date Range'),
                          Text(
                            _filterLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _pickDateRange,
                      child: const Text('Filter'),
                    ),
                    if (_filterStart != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _filterStart = null;
                            _filterEnd = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            style: AppTypography.titleMediumBold(context),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToCsv() async {
    setState(() => _isExporting = true);
    try {
      final sales = await _getSalesForExport();
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

      await _recordExport(fileFormat: 'csv', filePath: file.path);

      if (mounted) {
        await AppDialogService.success(context, title: 'Exported', message: 'CSV exported: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Export Failed', message: 'Failed to export CSV.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf() async {
    setState(() => _isExporting = true);
    try {
      final sales = await _getSalesForExport();
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Pinoy POS - Sales Report'),
            ),
            pw.Paragraph(
              text: 'Generated: ${DateTime.now().toLocal().toString().split('.')[0]}',
            ),
            pw.Paragraph(
              text: 'Date Range: $_filterLabel',
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text('Summary')),
            pw.TableHelper.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ["Today's Sales", 'PHP ${_todaySales.toStringAsFixed(2)}'],
                ['Month Sales', 'PHP ${_monthSales.toStringAsFixed(2)}'],
                ['Total Products', '$_totalProducts'],
                ['Low Stock Items', '$_lowStockCount'],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(8),
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text('Sales Detail')),
            pw.TableHelper.fromTextArray(
              headers: ['Receipt #', 'Date', 'Total'],
              data: sales
                  .map((s) => [
                        '${s.receiptNumber ?? s.id}',
                        s.createdAt.toLocal().toString().split('.')[0],
                        'PHP ${s.totalAmount.toStringAsFixed(2)}',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ],
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/pinoy_pos_sales_$timestamp.pdf');
      await file.writeAsBytes(await pdf.save());

      await _recordExport(fileFormat: 'pdf', filePath: file.path);

      if (mounted) {
        await AppDialogService.success(context, title: 'Exported', message: 'PDF exported: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Export Failed', message: 'Failed to export PDF.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}