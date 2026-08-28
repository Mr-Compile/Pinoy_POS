import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/reports_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
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
  bool _isExporting = false;
  ExportFormat? _selectedFormat;
  String? _lastExportPath;

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canExport = authNotifier.hasPermission('export_reports');
    final state = ref.watch(reportsProvider);

    if (state.isLoading) {
      return Scaffold(
        appBar: const AppHeader(title: 'Reports'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return Scaffold(
        appBar: const AppHeader(title: 'Reports'),
        body: _buildErrorState(state.error!),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'Reports',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(reportsProvider.notifier).load(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.storeInfoIncomplete) _buildStoreInfoBanner(context, state),
            _buildStoreHeader(context, state),
            const SizedBox(height: 24),
            _buildDateRangeFilter(context, state),
            const SizedBox(height: 24),
            _buildSummaryCards(context, state),
            const SizedBox(height: 24),
            _buildPaymentBreakdown(context, state),
            const SizedBox(height: 24),
            _buildTopProducts(context, state),
            const SizedBox(height: 24),
            _buildDailySales(context, state),
            const SizedBox(height: 24),
            _buildExportSection(context, state, canExport),
            if (_lastExportPath != null) ...[
              const SizedBox(height: 12),
              _buildLastExportInfo(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () => ref.read(reportsProvider.notifier).load(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreInfoBanner(BuildContext context, ReportsState state) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.store, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set up your store information',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    'Your store name, address, and contact will appear on receipts and exports.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const StoreInformationSettingsPage()),
              ).then((_) => ref.read(reportsProvider.notifier).refreshStoreInfo()),
              child: const Text('Set Up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreHeader(BuildContext context, ReportsState state) {
    final store = state.storeInfo;
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.storefront, color: cs.primary, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.storeName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (store.storeAddress.isNotEmpty)
                    Text(
                      store.storeAddress,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (store.storePhone.isNotEmpty)
                    Text(
                      'Contact: ${store.storePhone}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    'Currency: ${store.currency}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter(BuildContext context, ReportsState state) {
    final label = state.filterStart != null && state.filterEnd != null
        ? _formatRange(state.filterStart!, state.filterEnd!)
        : 'This month';

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _pickDateRange(context),
              child: const Text('Filter'),
            ),
            if (state.filterStart != null)
              TextButton(
                onPressed: () => ref.read(reportsProvider.notifier).clearDateRange(),
                child: const Text('Clear'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: ref.read(reportsProvider).filterStart ??
          DateTime(now.year, now.month, 1),
      end: ref.read(reportsProvider).filterEnd ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
    );

    if (picked != null && mounted) {
      final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
      final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      ref.read(reportsProvider.notifier).setDateRange(start, end);
    }
  }

  Widget _buildSummaryCards(BuildContext context, ReportsState state) {
    final currency = state.storeInfo.currency;
    return Column(
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
              _buildStatRow("Today's Sales", '$currency ${_todaySales(state)}'),
              const Divider(),
              _buildStatRow('Month Sales', '$currency ${_monthSales(state)}'),
              const Divider(),
              _buildStatRow('Total Transactions', '${state.totalTransactions}'),
              const Divider(),
              _buildStatRow('Total Products', '${state.totalProducts}'),
              const Divider(),
              _buildStatRow('Low Stock Items', '${state.lowStockCount}'),
            ],
          ),
        ),
      ],
    );
  }

  String _todaySales(ReportsState state) {
    return state.todaySales.toStringAsFixed(2);
  }

  String _monthSales(ReportsState state) {
    return state.monthSales.toStringAsFixed(2);
  }

  Widget _buildPaymentBreakdown(BuildContext context, ReportsState state) {
    if (state.paymentBreakdown.isEmpty) return const SizedBox.shrink();

    final currency = state.storeInfo.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Breakdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: state.paymentBreakdown.map((p) {
              return _buildStatRow(
                '${p.method} (${p.count})',
                '$currency ${p.total.toStringAsFixed(2)}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopProducts(BuildContext context, ReportsState state) {
    if (state.topProducts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Products',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: state.topProducts.asMap().entries.map((entry) {
              final p = entry.value;
              return _buildStatRow(
                '${entry.key + 1}. ${p.productName}',
                '${p.totalQuantity} sold',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDailySales(BuildContext context, ReportsState state) {
    if (state.dailySales.length < 2) return const SizedBox.shrink();

    final currency = state.storeInfo.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Sales',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: state.dailySales.map((d) {
              return _buildStatRow(
                '${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}',
                '$currency ${d.total.toStringAsFixed(2)} (${d.count} txn)',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: AppTypography.titleMediumBold(context),
          ),
        ],
      ),
    );
  }

  // ── Export UI ──────────────────────────────────────────────────────

  Widget _buildExportSection(BuildContext context, ReportsState state, bool canExport) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Export Report',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Row(
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
        ),
        const SizedBox(height: 16),
        if (canExport) _buildExportAction(state),
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

  Widget _buildExportAction(ReportsState state) {
    return SizedBox(
      width: double.infinity,
      child: LoadingButton(
        isLoading: _isExporting,
        onPressed: _selectedFormat != null ? () => _performExport(state) : null,
        label: _selectedFormat == null
            ? 'Select a format'
            : 'Export to ${_selectedFormat == ExportFormat.pdf ? 'PDF' : 'Excel'}',
      ),
    );
  }

  Widget _buildLastExportInfo() {
    return AppCard(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary, size: 20),
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

  Future<void> _performExport(ReportsState state) async {
    if (_selectedFormat == null) return;

    setState(() => _isExporting = true);

    try {
      final reportService = ref.read(reportServiceProvider);
      final DateTime start;
      final DateTime end;
      if (state.filterStart != null && state.filterEnd != null) {
        start = state.filterStart!;
        end = state.filterEnd!;
      } else {
        final now = DateTime.now();
        start = DateTime(now.year, now.month, 1);
        end = now;
      }

      final sales = await reportService.getSalesByDateRange(start, end);

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
        await _exportToPdf(state, sales, timestamp);
      } else {
        await _exportToExcel(state, sales, timestamp);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ReportsScreen] export failed: $e\n$st');
      }
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

  Future<void> _exportToPdf(
    ReportsState state,
    List<Sale> sales,
    String timestamp,
  ) async {
    final pdf = pw.Document();
    final store = state.storeInfo;
    final currency = store.currency;

    final paymentRows = state.paymentBreakdown
        .map((p) => [p.method, '${p.count}', '$currency ${p.total.toStringAsFixed(2)}'])
        .toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          _buildPdfHeader(store),
          pw.SizedBox(height: 16),
          pw.Text(
            'Sales Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(
            text: 'Generated: ${DateTime.now().toLocal().toString().split('.')[0]}',
          ),
          pw.Paragraph(text: 'Date Range: ${_formatRange(state.filterStart, state.filterEnd)}'),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Summary')),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ["Today's Sales", '$currency ${state.todaySales.toStringAsFixed(2)}'],
              ['Month Sales', '$currency ${state.monthSales.toStringAsFixed(2)}'],
              ['Total Products', '${state.totalProducts}'],
              ['Low Stock Items', '${state.lowStockCount}'],
              ['Total Transactions', '${state.totalTransactions}'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(8),
          ),
          if (paymentRows.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text('Payment Breakdown')),
            pw.TableHelper.fromTextArray(
              headers: ['Method', 'Count', 'Total ($currency)'],
              data: paymentRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ],
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Sales Detail')),
          pw.TableHelper.fromTextArray(
            headers: ['Receipt #', 'Date', 'Method', 'Total', 'Cash', 'Change'],
            data: sales
                .map((s) => [
                      '${s.receiptNumber ?? s.id}',
                      s.createdAt.toLocal().toString().split('.')[0],
                      s.paymentMethod,
                      '$currency ${s.totalAmount.toStringAsFixed(2)}',
                      '$currency ${s.cashReceived.toStringAsFixed(2)}',
                      '$currency ${s.change.toStringAsFixed(2)}',
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

    await ref.read(reportServiceProvider).recordExport(
          fileFormat: 'pdf',
          filePath: savePath,
          dateRangeStart: state.filterStart,
          dateRangeEnd: state.filterEnd,
        );

    if (mounted) {
      setState(() => _lastExportPath = savePath);
      await AppDialogService.success(context,
          title: 'Export Complete',
          message: 'PDF report saved successfully.');
    }
  }

  pw.Widget _buildPdfHeader(Settings store) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          store.storeName,
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF3567D6),
          ),
        ),
        if (store.storeAddress.isNotEmpty)
          pw.Text(store.storeAddress,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        if (store.storePhone.isNotEmpty)
          pw.Text('Contact: ${store.storePhone}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        if (store.receiptFooter?.isNotEmpty == true)
          pw.Text(store.receiptFooter!,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      ],
    );
  }

  Future<void> _exportToExcel(
    ReportsState state,
    List<Sale> sales,
    String timestamp,
  ) async {
    final excel = Excel.createExcel();
    final store = state.storeInfo;

    final sheet = excel['Sales Report'];
    excel.delete('Sheet1');

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue(store.storeName);
    if (store.storeAddress.isNotEmpty) {
      sheet.cell(CellIndex.indexByString('A2')).value =
          TextCellValue(store.storeAddress);
    }
    if (store.storePhone.isNotEmpty) {
      sheet.cell(CellIndex.indexByString('A3')).value =
          TextCellValue('Contact: ${store.storePhone}');
    }
    sheet.cell(CellIndex.indexByString('A5')).value =
        TextCellValue('${store.storeName} - Sales Report');
    sheet.cell(CellIndex.indexByString('A6')).value =
        TextCellValue('Generated: ${DateTime.now().toLocal().toString().split('.')[0]}');
    sheet.cell(CellIndex.indexByString('A7')).value =
        TextCellValue('Date Range: ${_formatRange(state.filterStart, state.filterEnd)}');

    int row = 9;
    sheet.cell(CellIndex.indexByString('A$row')).value =
        TextCellValue('Sales Detail');
    row++;
    sheet.appendRow([
      TextCellValue('Receipt #'),
      TextCellValue('Date'),
      TextCellValue('Payment Method'),
      TextCellValue('Total'),
      TextCellValue('Cash Received'),
      TextCellValue('Change'),
      TextCellValue('Notes'),
    ]);

    for (final s in sales) {
      sheet.appendRow([
        TextCellValue('${s.receiptNumber ?? s.id}'),
        TextCellValue(s.createdAt.toLocal().toString().split('.')[0]),
        TextCellValue(s.paymentMethod),
        DoubleCellValue(s.totalAmount),
        DoubleCellValue(s.cashReceived),
        DoubleCellValue(s.change),
        TextCellValue(s.notes ?? ''),
      ]);
    }

    row = sheet.rows.length + 2;
    sheet.cell(CellIndex.indexByString('A$row')).value =
        TextCellValue('Summary');
    row++;
    sheet.appendRow([TextCellValue("Today's Sales"), DoubleCellValue(state.todaySales)]);
    sheet.appendRow([TextCellValue('Month Sales'), DoubleCellValue(state.monthSales)]);
    sheet.appendRow([TextCellValue('Total Products'), IntCellValue(state.totalProducts)]);
    sheet.appendRow([TextCellValue('Low Stock Items'), IntCellValue(state.lowStockCount)]);
    sheet.appendRow([TextCellValue('Total Transactions'), IntCellValue(state.totalTransactions)]);

    if (state.paymentBreakdown.isNotEmpty) {
      row = sheet.rows.length + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value =
          TextCellValue('Payment Breakdown');
      row++;
      for (final p in state.paymentBreakdown) {
        sheet.appendRow([
          TextCellValue(p.method),
          IntCellValue(p.count),
          DoubleCellValue(p.total),
        ]);
      }
    }

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

    await ref.read(reportServiceProvider).recordExport(
          fileFormat: 'excel',
          filePath: savePath,
          dateRangeStart: state.filterStart,
          dateRangeEnd: state.filterEnd,
        );

    if (mounted) {
      setState(() => _lastExportPath = savePath);
      await AppDialogService.success(context,
          title: 'Export Complete',
          message: 'Excel report saved successfully.');
    }
  }

  String _formatRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'This month';
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(start)} to ${fmt(end)}';
  }
}
