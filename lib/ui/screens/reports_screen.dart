import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/reports_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/file_export_service.dart';
import 'package:pinoy_pos/ui/screens/settings/store_information_settings_page.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

enum ExportFormat { pdf, excel }

/// A confirmed sale bundled with its line items for export.
class _ExportSale {
  final Sale sale;
  final List<SaleItem> items;

  const _ExportSale({required this.sale, required this.items});

  int get itemCount => items.fold<int>(0, (sum, i) => sum + i.quantity);
}

/// Aggregated sales for a single product.
class _ProductSummary {
  final String name;
  int quantity = 0;
  double total = 0.0;

  _ProductSummary({required this.name});
}

/// Builds an aggregated "Sales by Product" list from export sales.
List<_ProductSummary> _salesByProduct(List<_ExportSale> exportSales) {
  final map = <String, _ProductSummary>{};
  for (final export in exportSales) {
    for (final item in export.items) {
      final name = item.productName ?? 'Product #${item.productId}';
      final existing = map.putIfAbsent(
          name, () => _ProductSummary(name: name));
      existing.quantity += item.quantity;
      existing.total += item.totalPrice;
    }
  }
  final list = map.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return list;
}

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

  // -- Export UI -------------------------------------------

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

  // -- Export execution ------------------------------------

  Future<void> _performExport(ReportsState state) async {
    if (_selectedFormat == null) return;

    setState(() => _isExporting = true);

    try {
      final reportService = ref.read(reportServiceProvider);
      final salesService = ref.read(salesServiceProvider);
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
          AppDialogService.info(context,
              title: 'No Sales',
              message:
                  'No sales were recorded for the selected period. Try adjusting the date filters.');
        }
        return;
      }

      final saleIds = sales.where((s) => s.id != null).map((s) => s.id!).toList();
      final items = await salesService.getSaleItemsBySaleIds(saleIds);
      final itemsBySaleId = <int, List<SaleItem>>{};
      for (final item in items) {
        if (item.saleId == null) continue;
        itemsBySaleId.putIfAbsent(item.saleId!, () => []).add(item);
      }

      final exportSales = sales
          .where((s) => s.id != null)
          .map((s) => _ExportSale(sale: s, items: itemsBySaleId[s.id] ?? []))
          .toList();

      final users = await ref.read(userServiceProvider).getAllUsers();
      final userNames = {
        for (final u in users)
          if (u.id != null)
            u.id!: u.fullName.isNotEmpty
                ? u.fullName
                : (u.username.isNotEmpty ? u.username : 'User ${u.id}')
      };

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      if (_selectedFormat == ExportFormat.pdf) {
        await _exportToPdf(state, exportSales, userNames, timestamp);
      } else {
        await _exportToExcel(state, exportSales, userNames, timestamp);
      }
    } catch (e, st) {
      debugPrint('[ReportsScreen] export failed: $e\n$st');
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Failed',
            message:
                'An error occurred during export. Please try again.\n\nDetails: $e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf(
    ReportsState state,
    List<_ExportSale> exportSales,
    Map<int, String> userNames,
    String timestamp,
  ) async {
    final pdf = pw.Document();
    final store = state.storeInfo;
    final currency = store.currency;

    final cs = AppColors.getLightColorScheme();

    PdfColor pdfColor(Color color) => PdfColor.fromInt(color.pdfValue);

    final primary = cs.primary;
    final onPrimary = cs.onPrimary;
    final successLight = pdfColor(AppSemanticColors.successContainer);
    final successDark = pdfColor(AppSemanticColors.success);

    PdfColor methodColor(String method) {
      final color = switch (method.toLowerCase()) {
        'cash' => cs.primary,
        'gcash' => AppSemanticColors.success,
        'card' => AppSemanticColors.info,
        _ => AppSemanticColors.neutral,
      };
      return pdfColor(color);
    }

    PdfColor methodBackground(String method) {
      final color = switch (method.toLowerCase()) {
        'cash' => cs.primaryContainer,
        'gcash' => AppSemanticColors.successContainer,
        'card' => AppSemanticColors.infoContainer,
        _ => AppSemanticColors.neutralContainer,
      };
      return pdfColor(color);
    }

    pw.Widget headerCell(String text) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.all(5),
          color: pdfColor(primary),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: pdfColor(onPrimary),
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
          ),
        );

    pw.Widget dataCell(
      String text, {
      PdfColor? backgroundColor,
      PdfColor? textColor,
      pw.Alignment? alignment,
      bool bold = false,
    }) =>
        pw.Container(
          alignment: alignment ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.all(4),
          color: backgroundColor,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: textColor,
              fontWeight: bold ? pw.FontWeight.bold : null,
              fontSize: 9,
            ),
          ),
        );

    pw.Table buildSummaryTable() {
      final data = [
        ["Today's Sales", '$currency ${state.todaySales.toStringAsFixed(2)}'],
        ['Month Sales', '$currency ${state.monthSales.toStringAsFixed(2)}'],
        ['Total Transactions', '${state.totalTransactions}'],
        ['Total Products', '${state.totalProducts}'],
        ['Low Stock Items', '${state.lowStockCount}'],
      ];

      return pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(),
          1: const pw.FixedColumnWidth(120),
        },
        border: pw.TableBorder.all(color: pdfColor(cs.outlineVariant), width: 0.5),
        children: [
          pw.TableRow(
            children: [headerCell('Metric'), headerCell('Value')],
          ),
          ...data.map((row) => pw.TableRow(
                children: [
                  dataCell(row[0]),
                  dataCell(
                    row[1],
                    alignment: pw.Alignment.centerRight,
                  ),
                ],
              )),
        ],
      );
    }

    pw.Table buildPaymentBreakdownTable() {
      return pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(),
          1: const pw.FixedColumnWidth(60),
          2: const pw.FixedColumnWidth(100),
        },
        border: pw.TableBorder.all(color: pdfColor(cs.outlineVariant), width: 0.5),
        children: [
          pw.TableRow(
            children: [
              headerCell('Method'),
              headerCell('Count'),
              headerCell('Total ($currency)'),
            ],
          ),
          ...state.paymentBreakdown.map((p) => pw.TableRow(
                children: [
                  dataCell(
                    p.method,
                    backgroundColor: methodBackground(p.method),
                    textColor: methodColor(p.method),
                  ),
                  dataCell('${p.count}', alignment: pw.Alignment.centerRight),
                  dataCell(
                    '$currency ${p.total.toStringAsFixed(2)}',
                    alignment: pw.Alignment.centerRight,
                  ),
                ],
              )),
        ],
      );
    }

    pw.Table buildTransactionsTable() {
      const headers = [
        'Receipt #',
        'Date/Time',
        'Cashier',
        'Customer',
        'Method',
        'Reference',
        'Items',
        'Total',
      ];

      final grandTotal = exportSales.fold<double>(
        0.0,
        (sum, e) => sum + e.sale.totalAmount,
      );

      return pw.Table(
        columnWidths: {
          0: const pw.FixedColumnWidth(70),
          1: const pw.FixedColumnWidth(95),
          2: const pw.FixedColumnWidth(75),
          3: const pw.FixedColumnWidth(70),
          4: const pw.FixedColumnWidth(50),
          5: const pw.FixedColumnWidth(75),
          6: const pw.FixedColumnWidth(40),
          7: const pw.FixedColumnWidth(60),
        },
        border: pw.TableBorder.all(color: pdfColor(cs.outlineVariant), width: 0.5),
        children: [
          pw.TableRow(
            children: headers.map(headerCell).toList(),
          ),
          ...exportSales.map((e) => pw.TableRow(
                children: [
                  dataCell('${e.sale.receiptNumber ?? e.sale.id}'),
                  dataCell(_formatDateTime(e.sale.createdAt)),
                  dataCell(userNames[e.sale.userId] ?? 'User ${e.sale.userId}'),
                  dataCell(e.sale.customerName ?? ''),
                  dataCell(
                    e.sale.paymentMethod,
                    backgroundColor: methodBackground(e.sale.paymentMethod),
                    textColor: methodColor(e.sale.paymentMethod),
                  ),
                  dataCell(e.sale.referenceNumber ?? ''),
                  dataCell('${e.itemCount}', alignment: pw.Alignment.centerRight),
                  dataCell(
                    '$currency ${e.sale.totalAmount.toStringAsFixed(2)}',
                    alignment: pw.Alignment.centerRight,
                  ),
                ],
              )),
          pw.TableRow(
            children: [
              dataCell(
                'Grand Total',
                backgroundColor: successLight,
                textColor: successDark,
                bold: true,
              ),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              pw.SizedBox.shrink(),
              dataCell(
                '$currency ${grandTotal.toStringAsFixed(2)}',
                backgroundColor: successLight,
                textColor: successDark,
                bold: true,
                alignment: pw.Alignment.centerRight,
              ),
            ],
          ),
        ],
      );
    }

    pw.Table buildSalesByProductTable() {
      final productSales = _salesByProduct(exportSales);
      final headers = ['Product', 'Qty', 'Revenue ($currency)'];

      final grandTotal = productSales.fold<double>(
        0.0,
        (sum, p) => sum + p.total,
      );

      final rows = <pw.TableRow>[
        pw.TableRow(children: headers.map(headerCell).toList()),
      ];

      for (final product in productSales) {
        rows.add(pw.TableRow(
          children: [
            dataCell(product.name),
            dataCell('${product.quantity}', alignment: pw.Alignment.centerRight),
            dataCell(
              '$currency ${product.total.toStringAsFixed(2)}',
              alignment: pw.Alignment.centerRight,
            ),
          ],
        ));
      }

      rows.add(pw.TableRow(
        children: [
          dataCell(
            'Grand Total',
            backgroundColor: successLight,
            textColor: successDark,
            bold: true,
          ),
          pw.SizedBox.shrink(),
          dataCell(
            '$currency ${grandTotal.toStringAsFixed(2)}',
            backgroundColor: successLight,
            textColor: successDark,
            bold: true,
            alignment: pw.Alignment.centerRight,
          ),
        ],
      ));

      return pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(),
          1: const pw.FixedColumnWidth(50),
          2: const pw.FixedColumnWidth(100),
        },
        border: pw.TableBorder.all(color: pdfColor(cs.outlineVariant), width: 0.5),
        children: rows,
      );
    }

    final paymentBreakdownRows = state.paymentBreakdown;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          _buildPdfHeader(store, pdfColor(primary)),
          pw.SizedBox(height: 16),
          pw.Text(
            'Sales Report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: pdfColor(primary),
            ),
          ),
          pw.Text(
            'Generated: ${_formatDateTime(DateTime.now())}',
            style: pw.TextStyle(fontSize: 10, color: pdfColor(cs.onSurfaceVariant)),
          ),
          pw.Text(
            'Date Range: ${_formatRange(state.filterStart, state.filterEnd)}',
            style: pw.TextStyle(fontSize: 10, color: pdfColor(cs.onSurfaceVariant)),
          ),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Summary')),
          buildSummaryTable(),
          if (paymentBreakdownRows.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text('Payment Breakdown')),
            buildPaymentBreakdownTable(),
          ],
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Sales Transactions')),
          buildTransactionsTable(),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text('Sales by Product')),
          buildSalesByProductTable(),
        ],
      ),
    );

    final fileName = 'pinoy_pos_sales_$timestamp.pdf';
    final bytes = Uint8List.fromList(await pdf.save());
    final savePath = await FileExportService.saveBytes(
      bytes: bytes,
      fileName: fileName,
      dialogTitle: 'Save Report',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath == null) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Cancelled', message: 'No save location selected.');
      }
      return;
    }

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

  pw.Widget _buildPdfHeader(Settings store, PdfColor primaryColor) {
    final bodyText = PdfColor.fromInt(
      AppColors.getLightColorScheme().onSurfaceVariant.pdfValue,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          store.storeName,
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
        if (store.storeAddress.isNotEmpty)
          pw.Text(store.storeAddress,
              style: pw.TextStyle(fontSize: 10, color: bodyText)),
        if (store.storePhone.isNotEmpty)
          pw.Text('Contact: ${store.storePhone}',
              style: pw.TextStyle(fontSize: 10, color: bodyText)),
        if (store.receiptFooter?.isNotEmpty == true)
          pw.Text(store.receiptFooter!,
              style: pw.TextStyle(fontSize: 10, color: bodyText)),
      ],
    );
  }

  Future<void> _exportToExcel(
    ReportsState state,
    List<_ExportSale> exportSales,
    Map<int, String> userNames,
    String timestamp,
  ) async {
    final excel = Excel.createExcel();
    final store = state.storeInfo;
    final currency = store.currency;

    excel.delete('Sheet1');

    final cs = AppColors.getLightColorScheme();

    final primary = cs.primary;
    final onPrimary = cs.onPrimary;
    final successLight = AppSemanticColors.successContainer;
    final successDark = AppSemanticColors.success;

    ExcelColor excelColor(Color color) => ExcelColor.fromHexString(color.excelHex);

    ExcelColor methodColor(String method) {
      final color = switch (method.toLowerCase()) {
        'cash' => cs.primary,
        'gcash' => AppSemanticColors.success,
        'card' => AppSemanticColors.info,
        _ => AppSemanticColors.neutral,
      };
      return excelColor(color);
    }

    ExcelColor methodBackground(String method) {
      final color = switch (method.toLowerCase()) {
        'cash' => cs.primaryContainer,
        'gcash' => AppSemanticColors.successContainer,
        'card' => AppSemanticColors.infoContainer,
        _ => AppSemanticColors.neutralContainer,
      };
      return excelColor(color);
    }

    CellStyle headerStyle() => CellStyle(
          backgroundColorHex: excelColor(primary),
          fontColorHex: excelColor(onPrimary),
          bold: true,
        );

    CellStyle totalStyle() => CellStyle(
          backgroundColorHex: excelColor(successLight),
          fontColorHex: excelColor(successDark),
          bold: true,
          numberFormat: NumFormat.standard_4,
          horizontalAlign: HorizontalAlign.Right,
        );

    CellStyle rightAlignStyle() => CellStyle(
          horizontalAlign: HorizontalAlign.Right,
        );

    CellStyle currencyStyle() => CellStyle(
          numberFormat: NumFormat.standard_4,
          horizontalAlign: HorizontalAlign.Right,
        );

    void writeCell(Sheet sheet, int row, int col, CellValue value,
        {CellStyle? style}) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: row,
      ));
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    void writeHeaderRow(Sheet sheet, int row, int startCol, List<String> headers) {
      for (var i = 0; i < headers.length; i++) {
        writeCell(
          sheet,
          row,
          startCol + i,
          TextCellValue(headers[i]),
          style: headerStyle(),
        );
      }
    }

    // -- Sales Summary sheet --
    final summary = excel['Sales Summary'];
    excel.setDefaultSheet('Sales Summary');

    writeCell(summary, 0, 0, TextCellValue(store.storeName));
    if (store.storeAddress.isNotEmpty) {
      writeCell(summary, 1, 0, TextCellValue(store.storeAddress));
    }
    if (store.storePhone.isNotEmpty) {
      writeCell(summary, 2, 0, TextCellValue('Contact: ${store.storePhone}'));
    }
    writeCell(summary, 4, 0, TextCellValue('${store.storeName} - Sales Report'));
    writeCell(
      summary,
      5,
      0,
      TextCellValue('Generated: ${_formatDateTime(DateTime.now())}'),
    );
    writeCell(
      summary,
      6,
      0,
      TextCellValue('Date Range: ${_formatRange(state.filterStart, state.filterEnd)}'),
    );

    var row = 8;
    writeCell(summary, row, 0, TextCellValue('Summary'));
    row++;

    final summaryRows = [
      ["Today's Sales", state.todaySales, true],
      ['Month Sales', state.monthSales, true],
      ['Total Transactions', state.totalTransactions.toDouble(), false],
      ['Total Products', state.totalProducts.toDouble(), false],
      ['Low Stock Items', state.lowStockCount.toDouble(), false],
    ];

    for (final entry in summaryRows) {
      final isCurrency = entry[2] as bool;
      writeCell(summary, row, 0, TextCellValue(entry[0] as String));
      if (isCurrency) {
        writeCell(
          summary,
          row,
          1,
          DoubleCellValue(entry[1] as double),
          style: currencyStyle(),
        );
      } else {
        writeCell(
          summary,
          row,
          1,
          IntCellValue((entry[1] as double).toInt()),
          style: rightAlignStyle(),
        );
      }
      row++;
    }

    if (state.paymentBreakdown.isNotEmpty) {
      row += 2;
      writeCell(summary, row, 0, TextCellValue('Payment Breakdown'));
      row++;
      final paymentHeaders = ['Method', 'Count', 'Total ($currency)'];
      writeHeaderRow(summary, row, 0, paymentHeaders);
      row++;
      for (final p in state.paymentBreakdown) {
        writeCell(
          summary,
          row,
          0,
          TextCellValue(p.method),
          style: CellStyle(
            backgroundColorHex: methodBackground(p.method),
            fontColorHex: methodColor(p.method),
          ),
        );
        writeCell(summary, row, 1, IntCellValue(p.count),
            style: rightAlignStyle());
        writeCell(
          summary,
          row,
          2,
          DoubleCellValue(p.total),
          style: currencyStyle(),
        );
        row++;
      }
    }

    row += 2;
    writeCell(summary, row, 0, TextCellValue('Sales Transactions'));
    row++;
    final transactionHeaders = [
      'Receipt #',
      'Date/Time',
      'Cashier',
      'Customer',
      'Payment Method',
      'Reference',
      'Items',
      'Total ($currency)',
    ];
    writeHeaderRow(summary, row, 0, transactionHeaders);
    row++;

    for (final export in exportSales) {
      final s = export.sale;
      writeCell(summary, row, 0, TextCellValue('${s.receiptNumber ?? s.id}'));
      writeCell(summary, row, 1, TextCellValue(_formatDateTime(s.createdAt)));
      writeCell(
          summary, row, 2, TextCellValue(userNames[s.userId] ?? 'User ${s.userId}'));
      writeCell(summary, row, 3, TextCellValue(s.customerName ?? ''));
      writeCell(
        summary,
        row,
        4,
        TextCellValue(s.paymentMethod),
        style: CellStyle(
          backgroundColorHex: methodBackground(s.paymentMethod),
          fontColorHex: methodColor(s.paymentMethod),
        ),
      );
      writeCell(summary, row, 5, TextCellValue(s.referenceNumber ?? ''));
      writeCell(summary, row, 6, IntCellValue(export.itemCount),
          style: rightAlignStyle());
      writeCell(
        summary,
        row,
        7,
        DoubleCellValue(s.totalAmount),
        style: currencyStyle(),
      );
      row++;
    }

    final grandTotal = exportSales.fold<double>(
      0.0,
      (sum, e) => sum + e.sale.totalAmount,
    );
    writeCell(summary, row, 0, TextCellValue('Grand Total'),
        style: totalStyle());
    for (var c = 1; c < 7; c++) {
      writeCell(summary, row, c, TextCellValue(''));
    }
    writeCell(
      summary,
      row,
      7,
      DoubleCellValue(grandTotal),
      style: totalStyle(),
    );

    for (var i = 0; i < transactionHeaders.length; i++) {
      summary.setColumnAutoFit(i);
    }

    // -- Line Items sheet --
    final itemsSheet = excel['Line Items'];
    final itemHeaders = [
      'Receipt #',
      'Date/Time',
      'Product',
      'Qty',
      'Unit Price ($currency)',
      'Line Total ($currency)',
      'Payment Method',
    ];
    writeHeaderRow(itemsSheet, 0, 0, itemHeaders);

    var itemRow = 1;
    for (final export in exportSales) {
      final s = export.sale;
      for (final item in export.items) {
        writeCell(
            itemsSheet, itemRow, 0, TextCellValue('${s.receiptNumber ?? s.id}'));
        writeCell(
            itemsSheet, itemRow, 1, TextCellValue(_formatDateTime(s.createdAt)));
        writeCell(
            itemsSheet,
            itemRow,
            2,
            TextCellValue(item.productName ?? 'Product #${item.productId}'));
        writeCell(itemsSheet, itemRow, 3, IntCellValue(item.quantity),
            style: rightAlignStyle());
        writeCell(
          itemsSheet,
          itemRow,
          4,
          DoubleCellValue(item.unitPrice),
          style: currencyStyle(),
        );
        writeCell(
          itemsSheet,
          itemRow,
          5,
          DoubleCellValue(item.totalPrice),
          style: currencyStyle(),
        );
        writeCell(
          itemsSheet,
          itemRow,
          6,
          TextCellValue(s.paymentMethod),
          style: CellStyle(
            backgroundColorHex: methodBackground(s.paymentMethod),
            fontColorHex: methodColor(s.paymentMethod),
          ),
        );
        itemRow++;
      }
    }

    writeCell(
      itemsSheet,
      itemRow,
      0,
      TextCellValue('Grand Total'),
      style: totalStyle(),
    );
    for (var c = 1; c < 5; c++) {
      writeCell(itemsSheet, itemRow, c, TextCellValue(''));
    }
    writeCell(
      itemsSheet,
      itemRow,
      5,
      DoubleCellValue(grandTotal),
      style: totalStyle(),
    );

    for (var i = 0; i < itemHeaders.length; i++) {
      itemsSheet.setColumnAutoFit(i);
    }

    // ── Sales by Product sheet ──
    final productSheet = excel['Sales by Product'];
    final productHeaders = ['Product', 'Qty', 'Revenue ($currency)'];
    writeHeaderRow(productSheet, 0, 0, productHeaders);

    final productSales = _salesByProduct(exportSales);
    var productRow = 1;
    for (final p in productSales) {
      writeCell(productSheet, productRow, 0, TextCellValue(p.name));
      writeCell(productSheet, productRow, 1, IntCellValue(p.quantity),
          style: rightAlignStyle());
      writeCell(
        productSheet,
        productRow,
        2,
        DoubleCellValue(p.total),
        style: currencyStyle(),
      );
      productRow++;
    }

    writeCell(
      productSheet,
      productRow,
      0,
      TextCellValue('Grand Total'),
      style: totalStyle(),
    );
    writeCell(productSheet, productRow, 1, TextCellValue(''));
    writeCell(
      productSheet,
      productRow,
      2,
      DoubleCellValue(grandTotal),
      style: totalStyle(),
    );

    for (var i = 0; i < productHeaders.length; i++) {
      productSheet.setColumnAutoFit(i);
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
    final savePath = await FileExportService.saveBytes(
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      dialogTitle: 'Save Report',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (savePath == null) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Export Cancelled', message: 'No save location selected.');
      }
      return;
    }

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

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0
        ? 12
        : hour > 12
            ? hour - 12
            : hour;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $displayHour:$minute $period';
  }
}
