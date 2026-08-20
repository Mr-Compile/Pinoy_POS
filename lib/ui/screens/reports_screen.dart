import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

enum ExportFormat { pdf, excel }

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
  ExportFormat? _selectedFormat;
  String? _lastExportPath;

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

  Future<List<Sale>> _getSalesForExport() async {
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
        appBar: AppHeader(
          title: 'Reports',
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'Reports',
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
              'Export Report',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            // Date range filter card
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
            const SizedBox(height: 16),
            // Format selection
            _buildFormatSelection(canExport),
            const SizedBox(height: 16),
            // Export button + last export path
            if (canExport) _buildExportAction(),
            if (_lastExportPath != null) ...[
              const SizedBox(height: 12),
              _buildLastExportInfo(),
            ],
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

  // ── Export UI ──────────────────────────────────────────────────────

  Widget _buildFormatSelection(bool canExport) {
    return Row(
      children: [
        Expanded(
          child: _buildFormatCard(
            icon: Icons.picture_as_pdf,
            label: 'PDF',
            description: 'Formatted report',
            format: ExportFormat.pdf,
            canExport: canExport,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: _buildFormatCard(
            icon: Icons.table_view,
            label: 'Excel',
            description: 'Spreadsheet (.xlsx)',
            format: ExportFormat.excel,
            canExport: canExport,
          ),
        ),
      ],
    );
  }

  Widget _buildFormatCard({
    required IconData icon,
    required String label,
    required String description,
    required ExportFormat format,
    required bool canExport,
  }) {
    final isSelected = _selectedFormat == format;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: canExport && !_isExporting
          ? () => setState(() => _selectedFormat = format)
          : null,
      child: AppCard(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              style: AppTypography.titleMediumBold(context),
            ),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xs),
            if (isSelected)
              Icon(Icons.check_circle, color: cs.primary, size: 20)
            else
              Icon(Icons.radio_button_unchecked,
                  color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildExportAction() {
    return SizedBox(
      width: double.infinity,
      child: LoadingButton(
        isLoading: _isExporting,
        onPressed: _selectedFormat != null ? _performExport : null,
        label: _selectedFormat == null
            ? 'Select a format'
            : 'Export to ${_selectedFormat == ExportFormat.pdf ? 'PDF' : 'Excel'}',
        child: _isExporting
            ? null
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_selectedFormat == ExportFormat.pdf
                      ? Icons.picture_as_pdf
                      : Icons.table_view),
                  const SizedBox(width: 8),
                  Text(
                    _selectedFormat == null
                        ? 'Select a format'
                        : 'Export to ${_selectedFormat == ExportFormat.pdf ? 'PDF' : 'Excel'}',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLastExportInfo() {
    return AppCard(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Export',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  _lastExportPath!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Export execution ───────────────────────────────────────────────

  Future<void> _performExport() async {
    if (_selectedFormat == null) return;

    setState(() => _isExporting = true);

    try {
      final sales = await _getSalesForExport();

      if (sales.isEmpty) {
        if (mounted) {
          AppDialogService.error(context,
              title: 'No Data',
              message: 'No sales data available for the selected period.');
        }
        return;
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      if (_selectedFormat == ExportFormat.pdf) {
        await _exportToPdf(sales, timestamp);
      } else {
        await _exportToExcel(sales, timestamp);
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Failed',
            message: 'An error occurred during export. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<String?> _pickSavePath(String fileName, String extension) async {
    if (kIsWeb) {
      return await FilePicker.platform.saveFile(
        dialogTitle: 'Save Report',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    }

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );

    return result;
  }

  Future<void> _exportToPdf(List<Sale> sales, String timestamp) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          _buildPdfLogo(),
          pw.SizedBox(height: 16),
          pw.Text(
            'Sales Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(
            text: 'Generated: ${DateTime.now().toLocal().toString().split('.')[0]}',
          ),
          pw.Paragraph(text: 'Date Range: $_filterLabel'),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Summary')),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ["Today's Sales", 'PHP ${_todaySales.toStringAsFixed(2)}'],
              ['Month Sales', 'PHP ${_monthSales.toStringAsFixed(2)}'],
              ['Total Products', '$_totalProducts'],
              ['Low Stock Items', '$_lowStockCount'],
              ['Total Transactions', '${sales.length}'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(8),
          ),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Sales Detail')),
          pw.TableHelper.fromTextArray(
            headers: ['Receipt #', 'Date', 'Total (PHP)', 'Cash (PHP)', 'Change (PHP)'],
            data: sales
                .map((s) => [
                      '${s.receiptNumber ?? s.id}',
                      s.createdAt.toLocal().toString().split('.')[0],
                      s.totalAmount.toStringAsFixed(2),
                      s.cashReceived.toStringAsFixed(2),
                      s.change.toStringAsFixed(2),
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

    final fileName = 'pinoy_pos_sales_$timestamp.pdf';
    final savePath = await _pickSavePath(fileName, 'pdf');

    if (savePath == null) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Cancelled', message: 'No save location selected.');
      }
      return;
    }

    final file = File(savePath);
    await file.writeAsBytes(await pdf.save());

    await _recordExport(fileFormat: 'pdf', filePath: savePath);

    if (mounted) {
      setState(() => _lastExportPath = savePath);
      await AppDialogService.success(context,
          title: 'Export Complete',
          message: 'PDF report saved successfully.');
    }
  }

  pw.Widget _buildPdfLogo() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 48,
          height: 60,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromInt(0xFF3567D6), width: 2),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Center(
            child: pw.Text(
              'P',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFFE91E63),
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Pinoy POS',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF3567D6),
              ),
            ),
            pw.Text(
              'Point of Sale System',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportToExcel(List<Sale> sales, String timestamp) async {
    final excel = Excel.createExcel();

    final sheet = excel['Sales Report'];
    excel.delete('Sheet1');

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Pinoy POS - Sales Report');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('Generated: ${DateTime.now().toLocal().toString().split('.')[0]}');
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Date Range: $_filterLabel');

    sheet.appendRow([
      TextCellValue('Receipt #'),
      TextCellValue('Date'),
      TextCellValue('Total (PHP)'),
      TextCellValue('Cash Received (PHP)'),
      TextCellValue('Change (PHP)'),
      TextCellValue('Notes'),
    ]);

    for (final s in sales) {
      sheet.appendRow([
        TextCellValue('${s.receiptNumber ?? s.id}'),
        TextCellValue(s.createdAt.toLocal().toString().split('.')[0]),
        DoubleCellValue(s.totalAmount),
        DoubleCellValue(s.cashReceived),
        DoubleCellValue(s.change),
        TextCellValue(s.notes ?? ''),
      ]);
    }

    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([TextCellValue('Summary')]);
    sheet.appendRow([TextCellValue("Today's Sales"), DoubleCellValue(_todaySales)]);
    sheet.appendRow([TextCellValue('Month Sales'), DoubleCellValue(_monthSales)]);
    sheet.appendRow([TextCellValue('Total Products'), IntCellValue(_totalProducts)]);
    sheet.appendRow([TextCellValue('Low Stock Items'), IntCellValue(_lowStockCount)]);
    sheet.appendRow([TextCellValue('Total Transactions'), IntCellValue(sales.length)]);

    final bytes = excel.save();
    if (bytes == null) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Failed', message: 'Failed to generate Excel file.');
      }
      return;
    }

    final fileName = 'pinoy_pos_sales_$timestamp.xlsx';
    final savePath = await _pickSavePath(fileName, 'xlsx');

    if (savePath == null) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Cancelled', message: 'No save location selected.');
      }
      return;
    }

    final file = File(savePath);
    await file.writeAsBytes(bytes);

    await _recordExport(fileFormat: 'excel', filePath: savePath);

    if (mounted) {
      setState(() => _lastExportPath = savePath);
      await AppDialogService.success(context,
          title: 'Export Complete',
          message: 'Excel report saved successfully.');
    }
  }
}