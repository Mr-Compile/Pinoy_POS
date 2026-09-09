import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/file_export_service.dart';
import 'package:pinoy_pos/services/pdf_font_service.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';

/// Supported report export formats.
enum ExportFormat {
  pdf,
  excel,
  csv;

  /// The file extension to use when saving.
  String get fileExtension => switch (this) {
        pdf => 'pdf',
        excel => 'xlsx',
        csv => 'csv',
      };

  /// The display name used in UI labels.
  String get displayName => switch (this) {
        pdf => 'PDF',
        excel => 'Excel',
        csv => 'CSV',
      };

  /// The value recorded in [ReportService.recordExport].
  String get fileFormat => switch (this) {
        pdf => 'pdf',
        excel => 'excel',
        csv => 'csv',
      };

  /// The MIME type used for browser downloads.
  String? get mimeType => switch (this) {
        pdf => 'application/pdf',
        excel =>
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        csv => 'text/csv',
      };
}

/// A confirmed sale bundled with its line items for export.
class ExportSaleBundle {
  final Sale sale;
  final List<SaleItem> items;
  final int itemCount;

  ExportSaleBundle({
    required this.sale,
    required this.items,
  }) : itemCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
}

/// Aggregated sales for a single product across all exported sales.
class ProductExportSummary {
  final String name;
  final int quantity;
  final double total;

  const ProductExportSummary({
    required this.name,
    required this.quantity,
    required this.total,
  });
}

/// Centralized service for generating and saving sales report exports.
///
/// Handles PDF, Excel, and CSV output for the sales analytics system,
/// keeping all export logic out of the UI layer.
class ReportExportService {
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();

  /// Exports the provided [analytics] as a PDF, Excel, or CSV report.
  ///
  /// Returns the saved file path when the file was saved and the export was
  /// recorded, or `null` when the user cancelled the save dialog or the report
  /// bytes could not be built.
  Future<String?> exportSalesReport({
    required SalesAnalytics analytics,
    required Settings store,
    required ExportFormat format,
  }) async {
    // Load all confirmed sales for the period so the export is not capped at
    // the 100-row preview limit used by the analytics UI.
    final allSales = await SalesService().getFilteredSales(
      start: analytics.bounds.start,
      end: analytics.bounds.end,
      paymentMethod: analytics.paymentMethod,
      paymentStatus: analytics.paymentStatus,
      userId: analytics.staffUserId,
      limit: null,
    );

    final bundles = await _buildBundles(allSales);
    final userNames = await _buildUserNames();

    var bytes = Uint8List(0);
    try {
      bytes = await switch (format) {
        ExportFormat.pdf => _buildPdf(analytics, store, bundles, userNames),
        ExportFormat.excel => _buildExcel(analytics, store, bundles, userNames),
        ExportFormat.csv => _buildCsv(analytics, store, bundles, userNames),
      };
    } catch (e, st) {
      debugPrint('[ReportExportService] Failed to build report bytes: $e\n$st');
      return null;
    }

    if (bytes.isEmpty) return null;

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final fileName = 'pinoy_pos_sales_$timestamp.${format.fileExtension}';

    final String? savePath;
    try {
      savePath = await FileExportService.saveBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Save Report',
        type: FileType.custom,
        allowedExtensions: [format.fileExtension],
        mimeType: format.mimeType,
      );
    } catch (e, st) {
      debugPrint('[ReportExportService] Save dialog failed: $e\n$st');
      return null;
    }

    if (savePath == null || savePath.isEmpty) return null;

    int? fileSize;
    if (!kIsWeb && !savePath.startsWith('content://')) {
      try {
        fileSize = await File(savePath).length();
      } catch (_) {
        fileSize = null;
      }
    }

    final reportNumber = await ReportService().nextReportNumber();
    await ReportService().recordExport(
      fileFormat: format.fileFormat,
      filePath: savePath,
      dateRangeStart: analytics.bounds.start,
      dateRangeEnd: analytics.bounds.end,
      fileSize: fileSize,
      reportNumber: reportNumber,
    );

    return savePath;
  }

  /// Generates a report for the current user and stores it in the app's
  /// reports directory as a submission to the Owner.
  ///
  /// This is the Staff report-submission workflow and is restricted to the
  /// `submit_reports` permission, which only Staff hold. The Owner exports
  /// sales directly via [exportSalesReport] and can never be routed into a
  /// staff submission, even if a caller bypasses the UI.
  ///
  /// Returns the saved report file path, or `null` if the report could not be
  /// generated or saved. On web this returns `null` because there is no
  /// persistent local report storage.
  Future<String?> submitSalesReport({
    required SalesAnalytics analytics,
    required Settings store,
    ExportFormat format = ExportFormat.pdf,
  }) async {
    if (kIsWeb) return null;
    if (!_sessionManager.hasPermission('submit_reports')) return null;

    final allSales = await SalesService().getFilteredSales(
      start: analytics.bounds.start,
      end: analytics.bounds.end,
      paymentMethod: analytics.paymentMethod,
      paymentStatus: analytics.paymentStatus,
      userId: analytics.staffUserId,
      limit: null,
    );

    final bundles = await _buildBundles(allSales);
    final userNames = await _buildUserNames();

    var bytes = Uint8List(0);
    try {
      bytes = await switch (format) {
        ExportFormat.pdf => _buildPdf(analytics, store, bundles, userNames),
        ExportFormat.excel => _buildExcel(analytics, store, bundles, userNames),
        ExportFormat.csv => _buildCsv(analytics, store, bundles, userNames),
      };
    } catch (e, st) {
      debugPrint('[ReportExportService] Failed to build report bytes: $e\n$st');
      return null;
    }

    if (bytes.isEmpty) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory(p.join(appDir.path, 'reports'));
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      final reportNumber = await ReportService().nextReportNumber();
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = 'sales_report_${reportNumber}_$timestamp.${format.fileExtension}';
      final filePath = p.join(reportsDir.path, fileName);

      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      // Store the relative path so backups can relocate the file directory.
      final storedPath = p.join('reports', fileName);

      final exportId = await ReportService().recordExport(
        fileFormat: format.fileFormat,
        filePath: storedPath,
        dateRangeStart: analytics.bounds.start,
        dateRangeEnd: analytics.bounds.end,
        fileSize: bytes.length,
        reportNumber: reportNumber,
      );

      if (exportId != null) {
        await ReportService().submitReport(exportId);
      }

      return storedPath;
    } catch (e, st) {
      debugPrint('[ReportExportService] Submit report failed: $e\n$st');
      return null;
    }
  }

  Future<List<ExportSaleBundle>> _buildBundles(List<Sale> sales) async {
    final saleIds = sales.where((s) => s.id != null).map((s) => s.id!).toList();
    final items = await _saleItemRepository.getBySaleIds(saleIds);

    final itemsBySaleId = <int, List<SaleItem>>{};
    for (final item in items) {
      if (item.saleId == null) continue;
      itemsBySaleId.putIfAbsent(item.saleId!, () => []).add(item);
    }

    return sales
        .where((s) => s.id != null)
        .map((s) => ExportSaleBundle(
              sale: s,
              items: itemsBySaleId[s.id!] ?? [],
            ))
        .toList();
  }

  Future<Map<int, String>> _buildUserNames() async {
    final users = await _userRepository.getAllActive();
    return {
      for (final u in users)
        if (u.id != null)
          u.id!: u.fullName.isNotEmpty
              ? u.fullName
              : (u.username.isNotEmpty ? u.username : 'User ${u.id}')
    };
  }

  List<ProductExportSummary> _buildProductSummaries(
    List<ExportSaleBundle> bundles,
  ) {
    final map = <String, ProductExportSummary>{};
    for (final bundle in bundles) {
      for (final item in bundle.items) {
        final name = item.productName ?? 'Product #${item.productId}';
        final existing = map[name];
        if (existing == null) {
          map[name] = ProductExportSummary(
            name: name,
            quantity: item.quantity,
            total: item.totalPrice,
          );
        } else {
          map[name] = ProductExportSummary(
            name: name,
            quantity: existing.quantity + item.quantity,
            total: existing.total + item.totalPrice,
          );
        }
      }
    }
    return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  Future<Uint8List> _buildPdf(
    SalesAnalytics analytics,
    Settings store,
    List<ExportSaleBundle> bundles,
    Map<int, String> userNames,
  ) async {
    await PdfFontService.ensureLoaded();

    final pdf = pw.Document(theme: PdfFontService.theme());
    final currency = store.currency;

    final cs = AppColors.getLightColorScheme();
    PdfColor toPdfColor(Color color) => PdfColor.fromInt(color.pdfValue);

    final primary = toPdfColor(cs.primary);
    final primaryDark = toPdfColor(AppColorTokens.primaryBlueStrong);
    final primaryLight = toPdfColor(AppColorTokens.primaryBlueLight);
    final onPrimary = toPdfColor(cs.onPrimary);
    final surfaceSoft = toPdfColor(AppColorTokens.lightSurfaceSoft);
    final surfaceSoft2 = toPdfColor(AppColorTokens.lightBackground);
    final outline = toPdfColor(cs.outlineVariant);
    final onSurface = toPdfColor(cs.onSurface);
    final onSurfaceVariant = toPdfColor(cs.onSurfaceVariant);
    final success = toPdfColor(AppSemanticColors.success);
    final successContainer = toPdfColor(AppSemanticColors.successContainer);

    String storeInitials(String name) {
      final parts = name.trim().split(RegExp(r'\s+'));
      final first = parts.isNotEmpty && parts.first.isNotEmpty ? parts.first[0] : '';
      final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
      return '$first$second'.toUpperCase();
    }

    PdfColor methodTextColor(String method) {
      return switch (method.toLowerCase()) {
        'cash' => primaryDark,
        'gcash' => success,
        'card' => primary,
        _ => onSurfaceVariant,
      };
    }

    PdfColor methodBackgroundColor(String method) {
      return switch (method.toLowerCase()) {
        'cash' => toPdfColor(AppColorTokens.primaryBlueLight.withValues(alpha: 0.16)),
        'gcash' => toPdfColor(AppSemanticColors.success.withValues(alpha: 0.16)),
        'card' => toPdfColor(AppSemanticColors.info.withValues(alpha: 0.16)),
        _ => toPdfColor(AppSemanticColors.neutralContainer),
      };
    }

    pw.Widget buildCell(
      pw.Widget child, {
      bool right = false,
      PdfColor? background,
    }) =>
        pw.Container(
          alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          color: background,
          child: child,
        );

    pw.Widget buildText(
      String text, {
      PdfColor? color,
      bool bold = false,
      pw.TextAlign? textAlign,
    }) =>
        pw.Text(
          text,
          style: PdfFontService.small(
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: color,
          ),
          textAlign: textAlign,
        );

    pw.Widget buildHeaderCell(String text, {bool right = false}) => buildCell(
          buildText(text, color: onPrimary, bold: true),
          background: primaryDark,
          right: right,
        );

    pw.Widget buildMethodBadge(String method) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: pw.BoxDecoration(
            color: methodBackgroundColor(method),
            borderRadius: pw.BorderRadius.circular(20),
          ),
          child: buildText(method, color: methodTextColor(method), bold: true),
        );

    pw.Widget buildStoreHeader() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 46,
                  height: 46,
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(12),
                    gradient: pw.LinearGradient(
                      colors: [primary, primaryDark],
                      begin: pw.Alignment.bottomLeft,
                      end: pw.Alignment.topRight,
                    ),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      storeInitials(store.storeName),
                      style: PdfFontService.title(
                        fontWeight: pw.FontWeight.bold,
                        color: onPrimary,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        store.storeName,
                        style: PdfFontService.headline(
                          fontWeight: pw.FontWeight.bold,
                          color: primaryDark,
                        ),
                      ),
                      if (store.storeAddress.isNotEmpty)
                        pw.Text(
                          store.storeAddress,
                          style: PdfFontService.body(color: onSurfaceVariant),
                        ),
                      if (store.storePhone.isNotEmpty)
                        pw.Text(
                          'Contact: ${store.storePhone}',
                          style: PdfFontService.body(color: onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Sales Summary',
                        style: PdfFontService.headline(
                          fontWeight: pw.FontWeight.bold,
                          color: primaryDark,
                        ),
                      ),
                      pw.Text(
                        'Generated: ${_formatDateTime(DateTime.now())}',
                        style: PdfFontService.body(color: onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Period',
                      style: PdfFontService.subhead(
                        fontWeight: pw.FontWeight.bold,
                        color: onSurfaceVariant,
                      ),
                    ),
                    pw.Text(
                      _formatPeriodLabel(analytics.bounds.start, analytics.bounds.end),
                      style: PdfFontService.body(color: onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

    pw.Widget buildMetricCard(String label, String value, {bool primaryCard = false}) =>
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(
              color: primaryCard ? surfaceSoft : surfaceSoft2,
              border: pw.Border.all(
                color: primaryCard ? primaryLight : outline,
                width: 0.5,
              ),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  value,
                  style: PdfFontService.title(
                    fontWeight: pw.FontWeight.bold,
                    color: primaryCard ? primaryDark : onSurface,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  label.toUpperCase(),
                  style: PdfFontService.small(
                    fontWeight: pw.FontWeight.bold,
                    color: onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );

    pw.Widget buildSummaryMetrics() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 16),
            pw.Row(
              children: [
                buildMetricCard(
                  'Total Sales',
                  '$currency ${analytics.totalSales.toStringAsFixed(2)}',
                  primaryCard: true,
                ),
                pw.SizedBox(width: 10),
                buildMetricCard('Transactions', '${analytics.transactionCount}'),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                buildMetricCard(
                  'Avg Transaction',
                  '$currency ${analytics.averageTransaction.toStringAsFixed(2)}',
                ),
                pw.SizedBox(width: 10),
                buildMetricCard('Items Sold', '${analytics.itemsSold}'),
              ],
            ),
          ],
        );

    pw.Widget buildTrendChart() {
      if (analytics.trend.isEmpty) return pw.SizedBox.shrink();
      final maxTotal = analytics.trend.fold<double>(
        0,
        (max, t) => t.total > max ? t.total : max,
      );
      const chartHeight = 70.0;

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 18),
          pw.Text(
            'Sales Trend',
            style: PdfFontService.subhead(
              fontWeight: pw.FontWeight.bold,
              color: primaryDark,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            height: chartHeight + 20,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: surfaceSoft2,
              border: pw.Border.all(color: outline, width: 0.5),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: analytics.trend.map((t) {
                final ratio = maxTotal == 0 ? 0.05 : t.total / maxTotal;
                final barHeight = chartHeight * ratio;
                return pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        height: barHeight,
                        decoration: pw.BoxDecoration(
                          gradient: pw.LinearGradient(
                            colors: [primaryDark, primaryLight],
                            begin: pw.Alignment.bottomCenter,
                            end: pw.Alignment.topCenter,
                          ),
                          borderRadius: const pw.BorderRadius.vertical(
                            top: pw.Radius.circular(4),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        DateFormat('MMM d').format(t.date.toLocal()),
                        style: PdfFontService.small(color: onSurfaceVariant),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    pw.Widget buildSectionTitle(String title) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
          child: pw.Text(
            title,
            style: PdfFontService.subhead(
              fontWeight: pw.FontWeight.bold,
              color: primaryDark,
            ),
          ),
        );

    pw.Table buildTable(
      List<String> headers,
      List<int?> widths,
      List<List<String>> rows,
      List<int> rightAlignCols, {
      List<int>? methodCols,
      List<String>? grandTotal,
    }) {
      final tableRows = <pw.TableRow>[
        pw.TableRow(
          children: List.generate(headers.length, (i) {
            return buildHeaderCell(headers[i], right: rightAlignCols.contains(i));
          }),
        ),
      ];

      for (final row in rows) {
        final cells = <pw.Widget>[];
        for (var i = 0; i < row.length; i++) {
          final text = row[i];
          final isMethod = methodCols != null && methodCols.contains(i);
          final isRight = rightAlignCols.contains(i);
          if (isMethod) {
            cells.add(buildCell(buildMethodBadge(text)));
          } else {
            cells.add(buildCell(
              buildText(text),
              right: isRight,
            ));
          }
        }
        tableRows.add(pw.TableRow(children: cells));
      }

      if (grandTotal != null) {
        final cells = <pw.Widget>[];
        for (var i = 0; i < grandTotal.length; i++) {
          final text = grandTotal[i];
          cells.add(text.isEmpty
              ? pw.SizedBox.shrink()
              : buildCell(
                  buildText(text, color: success, bold: true),
                  right: rightAlignCols.contains(i),
                  background: successContainer,
                ));
        }
        tableRows.add(pw.TableRow(children: cells));
      }

      final columnWidths = <int, pw.TableColumnWidth>{};
      for (var i = 0; i < widths.length; i++) {
        if (widths[i] == null) {
          columnWidths[i] = const pw.FlexColumnWidth();
        } else {
          columnWidths[i] = pw.FixedColumnWidth(widths[i]!.toDouble());
        }
      }

      return pw.Table(
        columnWidths: columnWidths,
        border: pw.TableBorder.all(color: outline, width: 0.5),
        children: tableRows,
      );
    }

    final paymentRows = analytics.paymentBreakdown
        .map((p) => [p.method, '${p.count}', '$currency ${p.total.toStringAsFixed(2)}'])
        .toList();

    final topProductRows = analytics.topProducts
        .map((p) => [p.productName, '${p.totalQuantity}', '$currency ${p.revenue.toStringAsFixed(2)}'])
        .toList();

    final transactionRows = bundles
        .map((e) => [
              '${e.sale.receiptNumber ?? e.sale.id}',
              _formatDateTime(e.sale.createdAt),
              userNames[e.sale.userId] ?? 'User ${e.sale.userId}',
              e.sale.customerName ?? '',
              e.sale.paymentMethod,
              e.sale.referenceNumber ?? '',
              '${e.itemCount}',
              '$currency ${e.sale.totalAmount.toStringAsFixed(2)}',
            ])
        .toList();

    final transactionGrandTotal = [
      'Grand Total',
      '',
      '',
      '',
      '',
      '',
      '',
      '$currency ${analytics.totalSales.toStringAsFixed(2)}',
    ];

    final lineItemRows = <List<String>>[];
    for (final bundle in bundles) {
      final s = bundle.sale;
      for (final item in bundle.items) {
        lineItemRows.add([
          '${s.receiptNumber ?? s.id}',
          _formatDateTime(s.createdAt),
          item.productName ?? 'Product #${item.productId}',
          '${item.quantity}',
          '$currency ${item.unitPrice.toStringAsFixed(2)}',
          '$currency ${item.totalPrice.toStringAsFixed(2)}',
          s.paymentMethod,
        ]);
      }
    }

    final productSales = _buildProductSummaries(bundles);
    final productRows = productSales
        .map((p) => [p.name, '${p.quantity}', '$currency ${p.total.toStringAsFixed(2)}'])
        .toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          buildStoreHeader(),
          buildSummaryMetrics(),
          buildTrendChart(),
          if (paymentRows.isNotEmpty) ...[
            buildSectionTitle('Payment Breakdown'),
            buildTable(
              ['Method', 'Count', 'Total ($currency)'],
              [null, 60, 100],
              paymentRows,
              [1, 2],
              methodCols: [0],
            ),
          ],
          if (topProductRows.isNotEmpty) ...[
            buildSectionTitle('Top Products'),
            buildTable(
              ['Product', 'Qty', 'Revenue ($currency)'],
              [null, 50, 100],
              topProductRows,
              [1, 2],
            ),
          ],
          if (transactionRows.isNotEmpty) ...[
            buildSectionTitle('Sales Transactions'),
            buildTable(
              [
                'Receipt #',
                'Date/Time',
                'Cashier',
                'Customer',
                'Method',
                'Reference',
                'Items',
                'Total'
              ],
              [70, 95, 75, 70, 50, 75, 40, 60],
              transactionRows,
              [6, 7],
              methodCols: [4],
              grandTotal: transactionGrandTotal,
            ),
          ],
          if (lineItemRows.isNotEmpty) ...[
            buildSectionTitle('Line Items'),
            buildTable(
              [
                'Receipt #',
                'Date/Time',
                'Product',
                'Qty',
                'Unit Price ($currency)',
                'Line Total ($currency)',
                'Payment Method'
              ],
              [70, 95, null, 40, 80, 80, 70],
              lineItemRows,
              [3, 4, 5],
              methodCols: [6],
              grandTotal: [
                'Grand Total',
                '',
                '',
                '',
                '',
                '$currency ${analytics.totalSales.toStringAsFixed(2)}',
                '',
              ],
            ),
          ],
          if (productRows.isNotEmpty) ...[
            buildSectionTitle('Sales by Product'),
            buildTable(
              ['Product', 'Qty', 'Revenue ($currency)'],
              [null, 50, 100],
              productRows,
              [1, 2],
              grandTotal: [
                'Grand Total',
                '',
                '$currency ${analytics.totalSales.toStringAsFixed(2)}',
              ],
            ),
          ],
        ],
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  Future<Uint8List> _buildExcel(
    SalesAnalytics analytics,
    Settings store,
    List<ExportSaleBundle> bundles,
    Map<int, String> userNames,
  ) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final cs = AppColors.getLightColorScheme();
    final currency = store.currency;

    final primary = AppColorTokens.primaryBlueStrong;
    final onPrimary = AppColorTokens.onPrimaryBlue;
    final success = AppSemanticColors.success;
    final successContainer = AppSemanticColors.successContainer;

    ExcelColor toExcelColor(Color color) => ExcelColor.fromHexString(color.excelHex);

    ExcelColor methodColor(String method) {
      return switch (method.toLowerCase()) {
        'cash' => toExcelColor(AppColorTokens.primaryBlueStrong),
        'gcash' => toExcelColor(success),
        'card' => toExcelColor(AppSemanticColors.info),
        _ => toExcelColor(AppSemanticColors.neutral),
      };
    }

    ExcelColor methodBackground(String method) {
      return switch (method.toLowerCase()) {
        'cash' => toExcelColor(cs.primaryContainer),
        'gcash' => toExcelColor(AppSemanticColors.successContainer),
        'card' => toExcelColor(AppSemanticColors.infoContainer),
        _ => toExcelColor(AppSemanticColors.neutralContainer),
      };
    }

    CellStyle headerStyle() => CellStyle(
          backgroundColorHex: toExcelColor(primary),
          fontColorHex: toExcelColor(onPrimary),
          bold: true,
        );

    CellStyle totalStyle() => CellStyle(
          backgroundColorHex: toExcelColor(successContainer),
          fontColorHex: toExcelColor(success),
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

    void writeCell(
      Sheet sheet,
      int row,
      int col,
      CellValue value, {
      CellStyle? style,
    }) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: row,
      ));
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    void writeText(Sheet sheet, int row, int col, String text, {CellStyle? style}) {
      writeCell(sheet, row, col, TextCellValue(text), style: style);
    }

    void writeHeaderRow(Sheet sheet, int row, List<String> headers) {
      for (var i = 0; i < headers.length; i++) {
        writeText(sheet, row, i, headers[i], style: headerStyle());
      }
    }

    final summary = excel['Summary'];
    excel.setDefaultSheet('Summary');

    writeText(summary, 0, 0, store.storeName, style: CellStyle(bold: true));
    if (store.storeAddress.isNotEmpty) {
      writeText(summary, 1, 0, store.storeAddress);
    }
    if (store.storePhone.isNotEmpty) {
      writeText(summary, 2, 0, 'Contact: ${store.storePhone}');
    }
    writeText(
      summary,
      4,
      0,
      '${store.storeName} - Sales Report',
      style: CellStyle(bold: true),
    );
    writeText(summary, 5, 0, 'Generated: ${_formatDateTime(DateTime.now())}');
    writeText(
      summary,
      6,
      0,
      'Period: ${_formatPeriodLabel(analytics.bounds.start, analytics.bounds.end)}',
    );

    var row = 8;
    writeText(summary, row, 0, 'Summary', style: CellStyle(bold: true));
    row++;

    final summaryRows = [
      ['Total Sales', analytics.totalSales, true],
      ['Transaction Count', analytics.transactionCount.toDouble(), false],
      ['Average Transaction', analytics.averageTransaction, true],
      ['Items Sold', analytics.itemsSold.toDouble(), false],
    ];

    for (final entry in summaryRows) {
      final isCurrency = entry[2] as bool;
      writeText(summary, row, 0, entry[0] as String, style: CellStyle(bold: true));
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

    if (analytics.paymentBreakdown.isNotEmpty) {
      row += 2;
      writeText(summary, row, 0, 'Payment Breakdown', style: CellStyle(bold: true));
      row++;
      writeHeaderRow(summary, row, ['Method', 'Count', 'Total ($currency)']);
      row++;
      for (final p in analytics.paymentBreakdown) {
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
        writeCell(summary, row, 1, IntCellValue(p.count), style: rightAlignStyle());
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

    if (analytics.trend.isNotEmpty) {
      row += 2;
      writeText(summary, row, 0, 'Trend', style: CellStyle(bold: true));
      row++;
      writeHeaderRow(summary, row, ['Date/Time', 'Total ($currency)', 'Transactions']);
      row++;
      for (final t in analytics.trend) {
        writeText(summary, row, 0, _formatDateTime(t.date));
        writeCell(
          summary,
          row,
          1,
          DoubleCellValue(t.total),
          style: currencyStyle(),
        );
        writeCell(summary, row, 2, IntCellValue(t.count), style: rightAlignStyle());
        row++;
      }
    }

    if (analytics.topProducts.isNotEmpty) {
      row += 2;
      writeText(summary, row, 0, 'Top Products', style: CellStyle(bold: true));
      row++;
      writeHeaderRow(summary, row, ['Product', 'Qty', 'Revenue ($currency)']);
      row++;
      for (final p in analytics.topProducts) {
        writeText(summary, row, 0, p.productName);
        writeCell(summary, row, 1, IntCellValue(p.totalQuantity), style: rightAlignStyle());
        writeCell(
          summary,
          row,
          2,
          DoubleCellValue(p.revenue),
          style: currencyStyle(),
        );
        row++;
      }
    }

    row += 2;
    writeText(summary, row, 0, 'Sales by Product', style: CellStyle(bold: true));
    row++;
    writeHeaderRow(summary, row, ['Product', 'Qty', 'Revenue ($currency)']);
    row++;

    final productSales = _buildProductSummaries(bundles);
    for (final p in productSales) {
      writeText(summary, row, 0, p.name);
      writeCell(summary, row, 1, IntCellValue(p.quantity), style: rightAlignStyle());
      writeCell(
        summary,
        row,
        2,
        DoubleCellValue(p.total),
        style: currencyStyle(),
      );
      row++;
    }

    writeCell(summary, row, 0, TextCellValue('Grand Total'), style: totalStyle());
    writeCell(summary, row, 1, TextCellValue(''), style: totalStyle());
    writeCell(
      summary,
      row,
      2,
      DoubleCellValue(analytics.totalSales),
      style: totalStyle(),
    );

    for (var i = 0; i < 3; i++) {
      summary.setColumnAutoFit(i);
    }

    final salesSheet = excel['Sales'];
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
    writeHeaderRow(salesSheet, 0, transactionHeaders);

    var salesRow = 1;
    for (final bundle in bundles) {
      final s = bundle.sale;
      writeText(salesSheet, salesRow, 0, '${s.receiptNumber ?? s.id}');
      writeText(salesSheet, salesRow, 1, _formatDateTime(s.createdAt));
      writeText(salesSheet, salesRow, 2, userNames[s.userId] ?? 'User ${s.userId}');
      writeText(salesSheet, salesRow, 3, s.customerName ?? '');
      writeCell(
        salesSheet,
        salesRow,
        4,
        TextCellValue(s.paymentMethod),
        style: CellStyle(
          backgroundColorHex: methodBackground(s.paymentMethod),
          fontColorHex: methodColor(s.paymentMethod),
        ),
      );
      writeText(salesSheet, salesRow, 5, s.referenceNumber ?? '');
      writeCell(salesSheet, salesRow, 6, IntCellValue(bundle.itemCount), style: rightAlignStyle());
      writeCell(
        salesSheet,
        salesRow,
        7,
        DoubleCellValue(s.totalAmount),
        style: currencyStyle(),
      );
      salesRow++;
    }

    writeCell(salesSheet, salesRow, 0, TextCellValue('Grand Total'), style: totalStyle());
    for (var c = 1; c < 7; c++) {
      writeCell(salesSheet, salesRow, c, TextCellValue(''), style: totalStyle());
    }
    writeCell(
      salesSheet,
      salesRow,
      7,
      DoubleCellValue(analytics.totalSales),
      style: totalStyle(),
    );

    for (var i = 0; i < transactionHeaders.length; i++) {
      salesSheet.setColumnAutoFit(i);
    }

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
    writeHeaderRow(itemsSheet, 0, itemHeaders);

    var itemRow = 1;
    for (final bundle in bundles) {
      final s = bundle.sale;
      for (final item in bundle.items) {
        writeText(itemsSheet, itemRow, 0, '${s.receiptNumber ?? s.id}');
        writeText(itemsSheet, itemRow, 1, _formatDateTime(s.createdAt));
        writeText(itemsSheet, itemRow, 2, item.productName ?? 'Product #${item.productId}');
        writeCell(itemsSheet, itemRow, 3, IntCellValue(item.quantity), style: rightAlignStyle());
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

    writeCell(itemsSheet, itemRow, 0, TextCellValue('Grand Total'), style: totalStyle());
    for (var c = 1; c < 5; c++) {
      writeCell(itemsSheet, itemRow, c, TextCellValue(''), style: totalStyle());
    }
    writeCell(
      itemsSheet,
      itemRow,
      5,
      DoubleCellValue(analytics.totalSales),
      style: totalStyle(),
    );

    for (var i = 0; i < itemHeaders.length; i++) {
      itemsSheet.setColumnAutoFit(i);
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('Failed to generate Excel file.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _buildCsv(
    SalesAnalytics analytics,
    Settings store,
    List<ExportSaleBundle> bundles,
    Map<int, String> userNames,
  ) async {
    final currency = store.currency;
    final rows = <List<dynamic>>[];

    rows.add([store.storeName]);
    if (store.storeAddress.isNotEmpty) rows.add([store.storeAddress]);
    if (store.storePhone.isNotEmpty) {
      rows.add(['Contact: ${store.storePhone}']);
    }
    rows.add([]);
    rows.add(['${store.storeName} - Sales Report']);
    rows.add(['Generated: ${_formatDateTime(DateTime.now())}']);
    rows.add([
      'Period: ${_formatPeriodLabel(analytics.bounds.start, analytics.bounds.end)}'
    ]);
    rows.add([]);

    rows.add(['Summary']);
    rows.add(['Metric', 'Value']);
    rows.add(['Total Sales', analytics.totalSales.toStringAsFixed(2)]);
    rows.add(['Transaction Count', analytics.transactionCount]);
    rows.add([
      'Average Transaction',
      analytics.averageTransaction.toStringAsFixed(2)
    ]);
    rows.add(['Items Sold', analytics.itemsSold]);
    rows.add([]);

    if (analytics.paymentBreakdown.isNotEmpty) {
      rows.add(['Payment Breakdown']);
      rows.add(['Method', 'Count', 'Total ($currency)']);
      for (final p in analytics.paymentBreakdown) {
        rows.add([p.method, p.count, p.total.toStringAsFixed(2)]);
      }
      rows.add([]);
    }

    if (analytics.trend.isNotEmpty) {
      rows.add(['Trend']);
      rows.add(['Date/Time', 'Total ($currency)', 'Transactions']);
      for (final t in analytics.trend) {
        rows.add([
          _formatDateTime(t.date),
          t.total.toStringAsFixed(2),
          t.count,
        ]);
      }
      rows.add([]);
    }

    if (analytics.topProducts.isNotEmpty) {
      rows.add(['Top Products']);
      rows.add(['Product', 'Qty', 'Revenue ($currency)']);
      for (final p in analytics.topProducts) {
        rows.add(
            [p.productName, p.totalQuantity, p.revenue.toStringAsFixed(2)]);
      }
      rows.add([]);
    }

    rows.add(['Sales Transactions']);
    rows.add([
      'Receipt #',
      'Date/Time',
      'Cashier',
      'Customer',
      'Payment Method',
      'Reference',
      'Items',
      'Total ($currency)',
    ]);

    for (final bundle in bundles) {
      final s = bundle.sale;
      rows.add([
        '${s.receiptNumber ?? s.id}',
        _formatDateTime(s.createdAt),
        userNames[s.userId] ?? 'User ${s.userId}',
        s.customerName ?? '',
        s.paymentMethod,
        s.referenceNumber ?? '',
        bundle.itemCount,
        s.totalAmount.toStringAsFixed(2),
      ]);
    }
    rows.add([
      'Grand Total',
      '',
      '',
      '',
      '',
      '',
      '',
      analytics.totalSales.toStringAsFixed(2)
    ]);
    rows.add([]);

    rows.add(['Line Items']);
    rows.add([
      'Receipt #',
      'Date/Time',
      'Product',
      'Qty',
      'Unit Price ($currency)',
      'Line Total ($currency)',
      'Payment Method',
    ]);

    for (final bundle in bundles) {
      final s = bundle.sale;
      for (final item in bundle.items) {
        rows.add([
          '${s.receiptNumber ?? s.id}',
          _formatDateTime(s.createdAt),
          item.productName ?? 'Product #${item.productId}',
          item.quantity,
          item.unitPrice.toStringAsFixed(2),
          item.totalPrice.toStringAsFixed(2),
          s.paymentMethod,
        ]);
      }
    }
    rows.add([
      'Grand Total',
      '',
      '',
      '',
      '',
      '',
      analytics.totalSales.toStringAsFixed(2)
    ]);
    rows.add([]);

    rows.add(['Sales by Product']);
    rows.add(['Product', 'Qty', 'Revenue ($currency)']);
    final productSales = _buildProductSummaries(bundles);
    for (final p in productSales) {
      rows.add([p.name, p.quantity, p.total.toStringAsFixed(2)]);
    }
    rows.add(['Grand Total', '', analytics.totalSales.toStringAsFixed(2)]);

    final csvString = const ListToCsvConverter().convert(rows);
    return Uint8List.fromList(utf8.encode(csvString));
  }
}

String _formatPeriodLabel(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'This month';
  final fmt = DateFormat('MMM d, yyyy');
  return '${fmt.format(start)} to ${fmt.format(end)}';
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
