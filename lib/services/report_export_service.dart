import 'dart:convert';
import 'dart:io';

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
  excel;

  /// The file extension to use when saving.
  String get fileExtension => switch (this) {
        pdf => 'pdf',
        excel => 'xlsx',
      };

  /// The display name used in UI labels.
  String get displayName => switch (this) {
        pdf => 'PDF',
        excel => 'Excel',
      };

  /// The value recorded in [ReportService.recordExport].
  String get fileFormat => switch (this) {
        pdf => 'pdf',
        excel => 'excel',
      };

  /// The MIME type used for browser downloads.
  String? get mimeType => switch (this) {
        pdf => 'application/pdf',
        excel =>
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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

/// Centralized service for generating and saving sales report exports.
///
/// Handles PDF and Excel output for the sales analytics system,
/// keeping all export logic out of the UI layer.
class ReportExportService {
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();

  /// Exports the provided [analytics] as a PDF or Excel report.
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

    // Generate an HTML companion preview for PDF and Excel exports.
    if (!kIsWeb &&
        (format == ExportFormat.pdf || format == ExportFormat.excel) &&
        !savePath.startsWith('content://')) {
      try {
        final htmlBytes = _buildHtml(analytics, store, bundles, userNames);
        final htmlPath = '${p.withoutExtension(savePath)}_preview.html';
        await File(htmlPath).writeAsBytes(htmlBytes, flush: true);
      } catch (e, st) {
        debugPrint('[ReportExportService] HTML companion write failed: $e\n$st');
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

      // Generate an HTML companion preview for PDF and Excel submissions.
      if (format == ExportFormat.pdf || format == ExportFormat.excel) {
        try {
          final htmlBytes = _buildHtml(analytics, store, bundles, userNames);
          final htmlPath = '${p.withoutExtension(filePath)}_preview.html';
          await File(htmlPath).writeAsBytes(htmlBytes, flush: true);
        } catch (e, st) {
          debugPrint('[ReportExportService] HTML companion write failed: $e\n$st');
        }
      }

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
    final outline = toPdfColor(cs.outline);
    final outlineVariant = toPdfColor(cs.outlineVariant);
    final onSurface = toPdfColor(cs.onSurface);
    final onSurfaceVariant = toPdfColor(cs.onSurfaceVariant);
    final lightTextSecondary = toPdfColor(AppColorTokens.lightTextSecondary);
    final success = toPdfColor(AppSemanticColors.success);
    final successContainer = toPdfColor(AppSemanticColors.successContainer);
    final onSuccessContainer = toPdfColor(AppSemanticColors.onSuccessContainer);

    PdfColor methodTextColor(String method) {
      return switch (method.toLowerCase()) {
        'cash' => primaryDark,
        'gcash' => success,
        'card' => primary,
        _ => lightTextSecondary,
      };
    }

    PdfColor methodBackgroundColor(String method) {
      return switch (method.toLowerCase()) {
        'cash' => toPdfColor(AppColorTokens.primaryBlueLight.withValues(alpha: 0.16)),
        'gcash' => toPdfColor(AppSemanticColors.success.withValues(alpha: 0.16)),
        'card' => toPdfColor(AppSemanticColors.info.withValues(alpha: 0.16)),
        _ => toPdfColor(AppColorTokens.textMuted.withValues(alpha: 0.18)),
      };
    }

    pw.Widget buildCell(
      pw.Widget child, {
      bool right = false,
    }) =>
        pw.Container(
          alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        );

    pw.Widget buildText(
      String text, {
      PdfColor? color,
      bool bold = false,
      pw.TextAlign? textAlign,
      double fontSize = 10,
      double letterSpacing = 0,
    }) {
      var style = PdfFontService.style(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : null,
        color: color,
      );
      if (letterSpacing != 0) {
        style = style.copyWith(letterSpacing: letterSpacing);
      }
      return pw.Text(
        text,
        style: style,
        textAlign: textAlign,
      );
    }

    pw.Widget buildHeaderCell(String text, {bool right = false}) => buildCell(
          buildText(text, color: onPrimary, bold: true, fontSize: 12),
          right: right,
        );

    pw.Widget buildMethodBadge(String method) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: pw.BoxDecoration(
            color: methodBackgroundColor(method),
            borderRadius: pw.BorderRadius.circular(20),
          ),
          child: buildText(
            method,
            color: methodTextColor(method),
            bold: true,
            fontSize: 10.5,
          ),
        );

    pw.Widget buildStoreHeader() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: primaryDark, width: 2),
                ),
              ),
              child: pw.Row(
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
                      child: buildText(
                        _storeInitials(store.storeName),
                        fontSize: 20,
                        bold: true,
                        color: onPrimary,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        buildText(
                          store.storeName,
                          fontSize: 18,
                          bold: true,
                          color: onSurface,
                        ),
                        if (store.storeAddress.isNotEmpty || store.storePhone.isNotEmpty)
                          buildText(
                            [
                              if (store.storeAddress.isNotEmpty) store.storeAddress,
                              if (store.storePhone.isNotEmpty) 'Contact: ${store.storePhone}',
                            ].join(' · '),
                            fontSize: 12,
                            color: lightTextSecondary,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      buildText(
                        'Sales Summary',
                        fontSize: 22,
                        bold: true,
                        color: primaryDark,
                      ),
                      buildText(
                        'Generated: ${_formatDateTime(DateTime.now())}',
                        fontSize: 12,
                        color: lightTextSecondary,
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    buildText(
                      'Period',
                      fontSize: 12,
                      bold: true,
                      color: lightTextSecondary,
                    ),
                    buildText(
                      _formatPeriodLabel(analytics.bounds.start, analytics.bounds.end),
                      fontSize: 12,
                      color: lightTextSecondary,
                      textAlign: pw.TextAlign.right,
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
                buildText(
                  value,
                  fontSize: 17,
                  bold: true,
                  color: primaryCard ? primaryDark : onSurface,
                ),
                pw.SizedBox(height: 6),
                buildText(
                  label.toUpperCase(),
                  fontSize: 10.5,
                  bold: true,
                  color: onSurfaceVariant,
                  letterSpacing: 0.4,
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
                  '$currency${analytics.totalSales.toStringAsFixed(2)}',
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
                  '$currency${analytics.averageTransaction.toStringAsFixed(2)}',
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
          pw.SizedBox(height: 16),
          buildText(
            'Sales Trend'.toUpperCase(),
            fontSize: 13,
            bold: true,
            color: primaryDark,
            letterSpacing: 0.4,
          ),
          pw.SizedBox(height: 10),
          pw.Container(
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
                      buildText(
                        DateFormat('MMM d').format(t.date.toLocal()),
                        fontSize: 9,
                        color: lightTextSecondary,
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
          padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
          child: buildText(
            title.toUpperCase(),
            fontSize: 13,
            bold: true,
            color: primaryDark,
            letterSpacing: 0.4,
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
          decoration: pw.BoxDecoration(color: primaryDark),
          children: List.generate(headers.length, (i) {
            return buildHeaderCell(headers[i], right: rightAlignCols.contains(i));
          }),
        ),
      ];

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final isLastDataRow = i == rows.length - 1;
        final hasBottomBorder = grandTotal != null || !isLastDataRow;
        final cells = <pw.Widget>[];
        for (var j = 0; j < row.length; j++) {
          final text = row[j];
          final isMethod = methodCols != null && methodCols.contains(j);
          final isRight = rightAlignCols.contains(j);
          if (isMethod) {
            cells.add(buildCell(buildMethodBadge(text)));
          } else {
            cells.add(buildCell(
              buildText(text, fontSize: 12),
              right: isRight,
            ));
          }
        }
        tableRows.add(pw.TableRow(
          decoration: hasBottomBorder
              ? pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: outlineVariant, width: 0.5),
                  ),
                )
              : null,
          children: cells,
        ));
      }

      if (grandTotal != null) {
        final cells = <pw.Widget>[];
        for (var i = 0; i < grandTotal.length; i++) {
          final text = grandTotal[i];
          cells.add(text.isEmpty
              ? pw.SizedBox.shrink()
              : buildCell(
                  buildText(text, color: onSuccessContainer, bold: true, fontSize: 12),
                  right: rightAlignCols.contains(i),
                ));
        }
        tableRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: successContainer),
          children: cells,
        ));
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
        border: null,
        children: tableRows,
      );
    }

    final paymentRows = analytics.paymentBreakdown
        .map((p) => [p.method, '${p.count}', '$currency${p.total.toStringAsFixed(2)}'])
        .toList();

    final paymentGrandTotal = [
      'Total',
      '${analytics.transactionCount}',
      '$currency${analytics.totalSales.toStringAsFixed(2)}',
    ];

    final topProductRows = analytics.topProducts
        .take(3)
        .map((p) => [p.productName, '${p.totalQuantity}', '$currency${p.revenue.toStringAsFixed(2)}'])
        .toList();

    final transactionRows = bundles
        .map((e) => [
              '${e.sale.receiptNumber ?? e.sale.id}',
              _formatShortDateTime(e.sale.createdAt),
              e.sale.customerName ?? 'GUEST',
              '${e.itemCount}',
              '$currency${e.sale.totalAmount.toStringAsFixed(2)}',
            ])
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
              ['Method', 'Count', 'Total'],
              [null, 60, 100],
              paymentRows,
              [1, 2],
              methodCols: [0],
              grandTotal: paymentGrandTotal,
            ),
          ],
          if (topProductRows.isNotEmpty) ...[
            buildSectionTitle('Top Products'),
            buildTable(
              ['Product', 'Qty', 'Revenue'],
              [null, 50, 100],
              topProductRows,
              [1, 2],
            ),
          ],
          if (transactionRows.isNotEmpty) ...[
            buildSectionTitle('Transactions'),
            buildTable(
              ['Receipt', 'Date/Time', 'Customer', 'Items', 'Total'],
              [70, 95, null, 40, 80],
              transactionRows,
              [3, 4],
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

    NumFormat currencyNumFormat() {
      final safeCurrency = currency.replaceAll('"', '""');
      return CustomNumericNumFormat(
        formatCode: '"$safeCurrency"#,##0.00',
      );
    }

    CellStyle headerStyle() => CellStyle(
          backgroundColorHex: toExcelColor(primary),
          fontColorHex: toExcelColor(onPrimary),
          bold: true,
          horizontalAlign: HorizontalAlign.Left,
        );

    CellStyle headerRightStyle() => CellStyle(
          backgroundColorHex: toExcelColor(primary),
          fontColorHex: toExcelColor(onPrimary),
          bold: true,
          horizontalAlign: HorizontalAlign.Right,
        );

    CellStyle totalStyle() => CellStyle(
          backgroundColorHex: toExcelColor(successContainer),
          fontColorHex: toExcelColor(success),
          bold: true,
          numberFormat: currencyNumFormat(),
          horizontalAlign: HorizontalAlign.Right,
        );

    CellStyle rightAlignStyle() => CellStyle(
          horizontalAlign: HorizontalAlign.Right,
        );

    CellStyle currencyStyle() => CellStyle(
          numberFormat: currencyNumFormat(),
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

    final summary = excel['Summary'];
    excel.setDefaultSheet('Summary');

    // Title row
    writeText(
      summary,
      0,
      0,
      '${store.storeName} - Sales Report',
      style: headerStyle(),
    );
    writeText(summary, 0, 1, '', style: headerStyle());

    // Summary metrics
    var row = 2;
    final summaryMetrics = [
      ('Total Sales', analytics.totalSales, true),
      ('Transaction Count', analytics.transactionCount.toDouble(), false),
      ('Average Transaction', analytics.averageTransaction, true),
      ('Items Sold', analytics.itemsSold.toDouble(), false),
    ];
    for (final metric in summaryMetrics) {
      writeText(summary, row, 0, metric.$1, style: CellStyle(bold: true));
      if (metric.$3) {
        writeCell(
          summary,
          row,
          1,
          DoubleCellValue(metric.$2),
          style: currencyStyle(),
        );
      } else {
        writeCell(
          summary,
          row,
          1,
          IntCellValue(metric.$2.toInt()),
          style: rightAlignStyle(),
        );
      }
      row++;
    }

    // Payment breakdown
    if (analytics.paymentBreakdown.isNotEmpty) {
      row++;
      writeText(summary, row, 0, 'Payment Method', style: headerStyle());
      writeText(summary, row, 1, 'Total', style: headerRightStyle());
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
        writeCell(
          summary,
          row,
          1,
          DoubleCellValue(p.total),
          style: currencyStyle(),
        );
        row++;
      }
      writeText(summary, row, 0, 'Grand Total', style: totalStyle());
      writeCell(
        summary,
        row,
        1,
        DoubleCellValue(analytics.totalSales),
        style: totalStyle(),
      );
      row++;
    }

    // Top products
    if (analytics.topProducts.isNotEmpty) {
      row++;
      writeText(summary, row, 0, 'Product', style: headerStyle());
      writeText(summary, row, 1, 'Revenue', style: headerRightStyle());
      row++;
      for (final p in analytics.topProducts.take(3)) {
        writeText(summary, row, 0, p.productName);
        writeCell(
          summary,
          row,
          1,
          DoubleCellValue(p.revenue),
          style: currencyStyle(),
        );
        row++;
      }
      writeText(summary, row, 0, 'Grand Total', style: totalStyle());
      writeCell(
        summary,
        row,
        1,
        DoubleCellValue(analytics.totalSales),
        style: totalStyle(),
      );
      row++;
    }

    for (var i = 0; i < 2; i++) {
      summary.setColumnAutoFit(i);
    }

    final salesSheet = excel['Sales'];
    final transactionHeaders = [
      'Receipt #',
      'Date/Time',
      'Cashier',
      'Customer',
      'Method',
      'Items',
      'Total',
    ];
    writeText(salesSheet, 0, 0, transactionHeaders[0], style: headerStyle());
    writeText(salesSheet, 0, 1, transactionHeaders[1], style: headerStyle());
    writeText(salesSheet, 0, 2, transactionHeaders[2], style: headerStyle());
    writeText(salesSheet, 0, 3, transactionHeaders[3], style: headerStyle());
    writeText(salesSheet, 0, 4, transactionHeaders[4], style: headerStyle());
    writeText(salesSheet, 0, 5, transactionHeaders[5], style: headerRightStyle());
    writeText(salesSheet, 0, 6, transactionHeaders[6], style: headerRightStyle());

    var salesRow = 1;
    for (final bundle in bundles) {
      final s = bundle.sale;
      writeText(salesSheet, salesRow, 0, '${s.receiptNumber ?? s.id}');
      writeText(salesSheet, salesRow, 1, _formatShortDateTime(s.createdAt));
      writeText(salesSheet, salesRow, 2, userNames[s.userId] ?? 'User ${s.userId}');
      writeText(salesSheet, salesRow, 3, s.customerName ?? 'GUEST');
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
      writeCell(salesSheet, salesRow, 5, IntCellValue(bundle.itemCount), style: rightAlignStyle());
      writeCell(
        salesSheet,
        salesRow,
        6,
        DoubleCellValue(s.totalAmount),
        style: currencyStyle(),
      );
      salesRow++;
    }

    writeText(salesSheet, salesRow, 0, 'Grand Total', style: totalStyle());
    for (var c = 1; c < 6; c++) {
      writeText(salesSheet, salesRow, c, '', style: totalStyle());
    }
    writeCell(
      salesSheet,
      salesRow,
      6,
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
      'Unit Price',
      'Line Total',
      'Payment Method',
    ];
    writeText(itemsSheet, 0, 0, itemHeaders[0], style: headerStyle());
    writeText(itemsSheet, 0, 1, itemHeaders[1], style: headerStyle());
    writeText(itemsSheet, 0, 2, itemHeaders[2], style: headerStyle());
    writeText(itemsSheet, 0, 3, itemHeaders[3], style: headerRightStyle());
    writeText(itemsSheet, 0, 4, itemHeaders[4], style: headerRightStyle());
    writeText(itemsSheet, 0, 5, itemHeaders[5], style: headerRightStyle());
    writeText(itemsSheet, 0, 6, itemHeaders[6], style: headerStyle());

    var itemRow = 1;
    for (final bundle in bundles) {
      final s = bundle.sale;
      for (final item in bundle.items) {
        writeText(itemsSheet, itemRow, 0, '${s.receiptNumber ?? s.id}');
        writeText(itemsSheet, itemRow, 1, _formatShortDateTime(s.createdAt));
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

    writeText(itemsSheet, itemRow, 0, 'Grand Total', style: totalStyle());
    for (var c = 1; c < 7; c++) {
      if (c == 5) {
        writeCell(
          itemsSheet,
          itemRow,
          c,
          DoubleCellValue(analytics.totalSales),
          style: totalStyle(),
        );
      } else {
        writeText(itemsSheet, itemRow, c, '', style: totalStyle());
      }
    }

    for (var i = 0; i < itemHeaders.length; i++) {
      itemsSheet.setColumnAutoFit(i);
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('Failed to generate Excel file.');
    }
    return Uint8List.fromList(bytes);
  }



  Uint8List _buildHtml(
    SalesAnalytics analytics,
    Settings store,
    List<ExportSaleBundle> bundles,
    Map<int, String> userNames,
  ) {
    final currency = store.currency;
    final generated = _formatDateTime(DateTime.now());
    final period = _formatPeriodLabel(analytics.bounds.start, analytics.bounds.end);

    final primary = _colorToHex(AppColorTokens.primaryBlueStrong);
    final primaryLight = _colorToHex(AppColorTokens.primaryBlueLight);
    final primaryDark = _colorToHex(AppColorTokens.lightPrimary);
    final surface = _colorToHex(AppColorTokens.lightBackground);
    final surfaceSoft = _colorToHex(AppColorTokens.lightSurfaceSoft);
    final border = _colorToHex(AppColorTokens.lightBorder);
    final divider = _colorToHex(AppColorTokens.lightDivider);
    final textPrimary = _colorToHex(AppColorTokens.lightTextPrimary);
    final textSecondary = _colorToHex(AppColorTokens.lightTextSecondary);
    final textMuted = _colorToHex(AppColorTokens.lightTextMuted);
    final successContainer = _colorToHex(AppSemanticColors.successContainer);
    final onSuccess = _colorToHex(AppSemanticColors.onSuccessContainer);

    String badgeFor(String method) {
      final lower = method.toLowerCase();
      if (lower == 'gcash') {
        return '<span class="badge" style="background:$successContainer;color:$onSuccess;">${_escapeHtml(method)}</span>';
      }
      final textColor = switch (lower) {
        'cash' => primary,
        'card' => primaryDark,
        _ => textSecondary,
      };
      return '<span class="badge" style="background:$surfaceSoft;color:$textColor;">${_escapeHtml(method)}</span>';
    }

    final maxTrend = analytics.trend.fold<double>(
      0,
      (m, t) => t.total > m ? t.total : m,
    );

    final contactParts = <String>[
      if (store.storeAddress.isNotEmpty) store.storeAddress,
      if (store.storePhone.isNotEmpty) 'Contact: ${store.storePhone}',
    ];

    final b = StringBuffer()
      ..write('<!DOCTYPE html>')
      ..write('<html lang="en">')
      ..write('<head>')
      ..write('<meta charset="UTF-8">')
      ..write('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
      ..write('<title>${_escapeHtml("${store.storeName} - Sales Report")}</title>')
      ..write('<style>');

    b.write('''
:root { --primary: $primary; --primary-light: $primaryLight; --primary-dark: $primaryDark; --surface: $surface; --surface-soft: $surfaceSoft; --border: $border; --divider: $divider; --text: $textPrimary; --text-2: $textSecondary; --text-3: $textMuted; --success-bg: $successContainer; --success-text: $onSuccess; }
* { box-sizing: border-box; }
body { margin: 0; padding: 16px; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; background: $surface; color: $textPrimary; }
.page { max-width: 900px; margin: 0 auto; background: #FFFFFF; border: 1px solid $border; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.04); }
.store-header { display: flex; align-items: center; padding-bottom: 16px; border-bottom: 2px solid $primaryDark; margin-bottom: 16px; }
.logo { width: 46px; height: 46px; border-radius: 12px; background: linear-gradient(135deg, $primary, $primaryDark); color: #FFFFFF; display: flex; align-items: center; justify-content: center; font-size: 20px; font-weight: 700; margin-right: 12px; flex-shrink: 0; }
.store-info h1 { margin: 0; font-size: 18px; color: $textPrimary; }
.store-info .meta { margin: 4px 0 0; font-size: 12px; color: $textSecondary; }
.title-row { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 16px; }
.title h2 { margin: 0; font-size: 22px; color: $primaryDark; }
.title .generated { margin: 4px 0 0; font-size: 12px; color: $textSecondary; }
.period { text-align: right; font-size: 12px; color: $textSecondary; }
.period strong { display: block; font-size: 14px; color: $textPrimary; font-weight: 700; }
.metric-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-bottom: 16px; }
.metric-card { border: 0.5px solid $border; border-radius: 12px; padding: 12px; background: $surfaceSoft; }
.metric-card.primary { border-color: $primaryLight; }
.metric-value { font-size: 17px; font-weight: 700; color: $textPrimary; }
.metric-card.primary .metric-value { color: $primaryDark; }
.metric-label { font-size: 10.5px; font-weight: 700; text-transform: uppercase; color: $textSecondary; margin-top: 6px; letter-spacing: 0.4px; }
.section-title { font-size: 13px; font-weight: 700; text-transform: uppercase; color: $primaryDark; margin: 16px 0 8px; letter-spacing: 0.4px; }
.chart { background: $surfaceSoft; border: 0.5px solid $border; border-radius: 12px; padding: 12px; display: flex; align-items: flex-end; gap: 8px; height: 120px; }
.bar-wrapper { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: flex-end; min-width: 0; }
.bar { width: 100%; max-width: 24px; border-radius: 4px 4px 0 0; background: linear-gradient(to top, $primaryDark, $primaryLight); }
.bar-label { font-size: 9px; color: $textSecondary; margin-top: 4px; text-align: center; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; width: 100%; }
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th { text-align: left; padding: 10px 12px; background: $primaryDark; color: #FFFFFF; font-weight: 700; }
td { padding: 10px 12px; border-bottom: 1px solid $divider; color: $textPrimary; }
.right { text-align: right; }
.total-row { background: $successContainer !important; color: $onSuccess; font-weight: 700; }
.total-row td { color: $onSuccess; border-bottom: none; }
.badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-weight: 700; font-size: 10.5px; }
@media (max-width: 600px) { .page { padding: 16px; } .metric-grid { grid-template-columns: 1fr; } .title-row { flex-direction: column; align-items: flex-start; gap: 8px; } .period { text-align: left; } }
''');

    b
      ..write('</style>')
      ..write('</head>')
      ..write('<body>')
      ..write('<div class="page">');

    // Store header
    b.write('<div class="store-header">');
    b.write('<div class="logo">${_escapeHtml(_storeInitials(store.storeName))}</div>');
    b.write('<div class="store-info">');
    b.write('<h1>${_escapeHtml(store.storeName)}</h1>');
    if (contactParts.isNotEmpty) {
      b.write('<p class="meta">${_escapeHtml(contactParts.join(' · '))}</p>');
    }
    b.write('</div></div>');

    // Title row
    b.write('<div class="title-row">');
    b.write('<div class="title"><h2>Sales Summary</h2>');
    b.write('<p class="generated">Generated: ${_escapeHtml(generated)}</p></div>');
    b.write('<div class="period">Period<br><strong>${_escapeHtml(period)}</strong></div>');
    b.write('</div>');

    // Metrics
    b.write('<div class="metric-grid">');
    b.write('<div class="metric-card primary"><div class="metric-value">${_escapeHtml(currency)}${analytics.totalSales.toStringAsFixed(2)}</div><div class="metric-label">Total Sales</div></div>');
    b.write('<div class="metric-card"><div class="metric-value">${analytics.transactionCount}</div><div class="metric-label">Transactions</div></div>');
    b.write('<div class="metric-card"><div class="metric-value">${_escapeHtml(currency)}${analytics.averageTransaction.toStringAsFixed(2)}</div><div class="metric-label">Average Transaction</div></div>');
    b.write('<div class="metric-card"><div class="metric-value">${analytics.itemsSold}</div><div class="metric-label">Items Sold</div></div>');
    b.write('</div>');

    // Trend
    if (analytics.trend.isNotEmpty) {
      b.write('<div class="section-title">Sales Trend</div>');
      b.write('<div class="chart">');
      for (final t in analytics.trend) {
        final ratio = maxTrend == 0 ? 0.05 : t.total / maxTrend;
        final height = (90 * ratio).toStringAsFixed(1);
        final label = DateFormat('MMM d').format(t.date.toLocal());
        b.write('<div class="bar-wrapper"><div class="bar" style="height:${height}px"></div><div class="bar-label">${_escapeHtml(label)}</div></div>');
      }
      b.write('</div>');
    }

    // Payment breakdown
    if (analytics.paymentBreakdown.isNotEmpty) {
      b.write('<div class="section-title">Payment Breakdown</div>');
      b.write('<div class="table-wrap"><table><thead><tr><th>Method</th><th class="right">Count</th><th class="right">Total</th></tr></thead><tbody>');
      for (final p in analytics.paymentBreakdown) {
        b.write('<tr><td>${badgeFor(p.method)}</td><td class="right">${p.count}</td><td class="right">${_escapeHtml(currency)}${p.total.toStringAsFixed(2)}</td></tr>');
      }
      b.write('<tr class="total-row"><td>Total</td><td class="right">${analytics.transactionCount}</td><td class="right">${_escapeHtml(currency)}${analytics.totalSales.toStringAsFixed(2)}</td></tr>');
      b.write('</tbody></table></div>');
    }

    // Top products
    if (analytics.topProducts.isNotEmpty) {
      b.write('<div class="section-title">Top Products</div>');
      b.write('<div class="table-wrap"><table><thead><tr><th>Product</th><th class="right">Qty</th><th class="right">Revenue</th></tr></thead><tbody>');
      for (final p in analytics.topProducts.take(3)) {
        b.write('<tr><td>${_escapeHtml(p.productName)}</td><td class="right">${p.totalQuantity}</td><td class="right">${_escapeHtml(currency)}${p.revenue.toStringAsFixed(2)}</td></tr>');
      }
      b.write('</tbody></table></div>');
    }

    // Transactions
    if (bundles.isNotEmpty) {
      b.write('<div class="section-title">Transactions</div>');
      b.write('<div class="table-wrap"><table><thead><tr>');
      b.write('<th>Receipt</th>');
      b.write('<th>Date/Time</th>');
      b.write('<th>Customer</th>');
      b.write('<th class="right">Items</th>');
      b.write('<th class="right">Total</th>');
      b.write('</tr></thead><tbody>');
      for (final bundle in bundles) {
        final s = bundle.sale;
        b.write('<tr>');
        b.write('<td>${_escapeHtml('${s.receiptNumber ?? s.id}')}</td>');
        b.write('<td>${_escapeHtml(_formatShortDateTime(s.createdAt))}</td>');
        b.write('<td>${_escapeHtml(s.customerName ?? 'GUEST')}</td>');
        b.write('<td class="right">${bundle.itemCount}</td>');
        b.write('<td class="right">${_escapeHtml(currency)}${s.totalAmount.toStringAsFixed(2)}</td>');
        b.write('</tr>');
      }
      b.write('</tbody></table></div>');
    }

    b.write('</div>');
    b.write('</body></html>');

    return Uint8List.fromList(utf8.encode(b.toString()));
  }

}

String _formatPeriodLabel(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'This month';
  final fmt = DateFormat('MMM d, yyyy');
  return '${fmt.format(start)} - ${fmt.format(end)}';
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
  return '${DateFormat('MMM d, yyyy').format(local)} $displayHour:$minute $period';
}

String _formatShortDateTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour == 0
      ? 12
      : hour > 12
          ? hour - 12
          : hour;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${DateFormat('MMM d').format(local)} $displayHour:$minute $period';
}

String _colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _escapeHtml(String text) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(text);

String _storeInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final first = parts.isNotEmpty && parts.first.isNotEmpty ? parts.first[0] : '';
  final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
  return '$first$second'.toUpperCase();
}
