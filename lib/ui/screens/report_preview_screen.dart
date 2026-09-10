import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/export_history.dart';
import 'package:pinoy_pos/services/file_export_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// In-app report preview.
///
/// * PDF: rendered with [PdfPreview] so the user can scroll/zoom pages.
/// * Excel: rendered as a readable data table from the first sheet.
class ReportPreviewScreen extends StatefulWidget {
  final ExportHistory report;
  final String? staffName;

  const ReportPreviewScreen({
    super.key,
    required this.report,
    this.staffName,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool _isLoading = true;
  String? _error;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _bytes = null;
    });

    try {
      final bytes = await _readFile(widget.report.filePath);
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _error = 'The report file could not be read.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _bytes = bytes;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('[ReportPreviewScreen] load failed: $e\n$st');
      setState(() {
        _error = 'Unable to load the report.';
        _isLoading = false;
      });
    }
  }

  Future<Uint8List?> _readFile(String path) async {
    if (kIsWeb) {
      // Web cannot read arbitrary filesystem paths; show metadata only.
      return null;
    }

    if (path.startsWith('content://')) {
      // Content URIs cannot be read with dart:io; the file picker has already
      // stored a copy in the app reports directory for submitted reports.
      return null;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final relative = p.join(appDir.path, path);
    final absolute = p.isAbsolute(path) ? path : relative;

    final file = File(absolute);
    if (await file.exists()) {
      return file.readAsBytes();
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppHeader(
        title: 'Report Preview',
        subtitle: 'Sales Report · ${widget.report.fileFormat.toUpperCase()}',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadFile,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading report...')
          : _buildBody(context, cs),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs) {
    if (_error != null) {
      return ErrorState(
        title: 'Report unavailable',
        message: _error,
        onRetry: _loadFile,
      );
    }

    final bytes = _bytes;
    final metadata = _buildMetadataOnly(context);

    if (bytes == null || bytes.isEmpty) {
      return metadata;
    }

    return Column(
      children: [
        metadata,
        Expanded(
          child: _isPdf
              ? _buildPdfPreview(bytes)
              : _buildSpreadsheetPreview(bytes),
        ),
        _buildActions(context, cs),
      ],
    );
  }

  bool get _isPdf => widget.report.fileFormat.toLowerCase() == 'pdf';

  Widget _buildPdfPreview(Uint8List bytes) {
    return PdfPreview(
      build: (format) async => bytes,
      allowPrinting: false,
      allowSharing: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      scrollViewDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
    );
  }

  Widget _buildSpreadsheetPreview(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      final keys = excel.tables.keys;
      final selected = keys.contains('Sales')
          ? 'Sales'
          : (keys.contains('Line Items') ? 'Line Items' : keys.first);
      final sheet = excel.tables[selected]!;
      final headers = sheet.row(0).map((cell) => cell?.value?.toString() ?? '').toList();
      final rows = sheet.rows.skip(1).take(50).toList();

      return LayoutBuilder(
        builder: (context, constraints) {
          if (layoutClassFor(constraints.maxWidth) == LayoutClass.compact) {
            return ListView.builder(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < headers.length && i < row.length; i++)
                          _SpreadsheetCellRow(
                            header: headers[i],
                            value: row[i]?.value?.toString() ?? '',
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          final cs = Theme.of(context).colorScheme;

          final numericHeaderKeywords = const [
            'qty',
            'quantity',
            'items',
            'total',
            'unit price',
            'line total',
            'revenue',
            'count',
            'amount',
          ];
          final isNumericColumn = headers
              .map((h) => numericHeaderKeywords.any((k) => h.toLowerCase().contains(k)))
              .toList();

          return AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    cs.surfaceContainerHigh,
                  ),
                  headingTextStyle: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  dataTextStyle: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(color: cs.outline),
                  ),
                  columns: headers
                      .asMap()
                      .entries
                      .map((e) => DataColumn(
                            label: Align(
                              alignment: isNumericColumn[e.key]
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(e.value),
                            ),
                          ))
                      .toList(),
                  rows: rows
                      .map((row) => DataRow(
                            cells: row
                                .asMap()
                                .entries
                                .map((e) => DataCell(
                                      Align(
                                        alignment: isNumericColumn.length > e.key && isNumericColumn[e.key]
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Text(e.value?.value?.toString() ?? ''),
                                      ),
                                    ))
                                .toList(),
                          ))
                      .toList(),
                ),
              ),
            ),
          );
        },
      );
    } catch (e, st) {
      debugPrint('[ReportPreviewScreen] spreadsheet decode failed: $e\n$st');
      return _buildMetadataOnly(context);
    }
  }

  Widget _buildMetadataOnly(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');
    final date = widget.report.submittedAt ?? widget.report.createdAt;

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report Details',
              style: AppTypography.titleMediumBold(context),
            ),
            const SizedBox(height: 14),
            _DetailRow(label: 'Report #', value: widget.report.reportNumber ?? '—'),
            _DetailRow(
              label: 'Format',
              valueWidget: AppStatusChip(
                label: widget.report.fileFormat.toUpperCase(),
                color: AppSemanticColors.resolve(
                  AppSemanticColors.success,
                  Theme.of(context).brightness,
                ),
              ),
            ),
            _DetailRow(
              label: 'Period',
              value: _periodLabel(),
            ),
            _DetailRow(
              label: 'Submitted by',
              value: widget.staffName ?? '—',
            ),
            _DetailRow(
              label: 'Date',
              value: dateFormat.format(date.toLocal()),
            ),
            if (widget.report.fileSize != null)
              _DetailRow(
                label: 'Size',
                value: '${(widget.report.fileSize! / 1024).toStringAsFixed(1)} KB',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final exportButton = AppButton.filled(
      label: 'Export',
      icon: Icons.download,
      onPressed: _export,
    );
    final shareButton = _bytes != null
        ? AppButton.outlined(
            label: 'Share',
            icon: Icons.share,
            color: AppButtonColor.neutral,
            onPressed: _share,
          )
        : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (layoutClassFor(constraints.maxWidth) == LayoutClass.compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  exportButton,
                  if (shareButton != null) ...[
                    const SizedBox(height: Spacing.sm),
                    shareButton,
                  ],
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: exportButton),
                if (shareButton != null) ...[
                  const SizedBox(width: Spacing.md),
                  Expanded(child: shareButton),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _periodLabel() {
    final start = widget.report.dateRangeStart;
    final end = widget.report.dateRangeEnd;
    if (start == null || end == null) return '—';
    final fmt = DateFormat('MMM d, yyyy');
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }

  Future<void> _export() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      await AppDialogService.warning(
        context,
        title: 'Cannot export',
        message: 'The report file is not available on this device.',
      );
      return;
    }

    final ext = widget.report.fileFormat.toLowerCase();
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final fileName = '${_sanitizedTitle()}_$timestamp.$ext';

    final mime = switch (widget.report.fileFormat) {
      'pdf' => 'application/pdf',
      'excel' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };

    final saved = await FileExportService.saveBytes(
      bytes: bytes,
      fileName: fileName,
      dialogTitle: 'Save Report',
      type: FileType.custom,
      allowedExtensions: [ext],
      mimeType: mime,
    );

    if (mounted && saved != null && saved.isNotEmpty) {
      await AppDialogService.success(
        context,
        title: 'Report Exported',
        message: 'The report was saved to:',
        details: saved,
      );
    }
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty || kIsWeb) return;

    // Best-effort share by saving to a temporary public location.
    final dir = await getTemporaryDirectory();
    final ext = widget.report.fileFormat.toLowerCase();
    final out = File(p.join(dir.path, 'shared_report.$ext'));
    await out.writeAsBytes(bytes);

    if (mounted) {
      await AppDialogService.success(
        context,
        title: 'Share ready',
        message: 'The file is at:',
        details: out.path,
      );
    }
  }

  String _sanitizedTitle() {
    return 'report'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
  }
}

class _SpreadsheetCellRow extends StatelessWidget {
  final String header;
  final String value;

  const _SpreadsheetCellRow({required this.header, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              header,
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmall(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;

  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: AppTypography.bodyMedium(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: valueWidget != null
                ? valueWidget!
                : Text(
                    value ?? '',
                    style: AppTypography.bodyMedium(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
