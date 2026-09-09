import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';

/// A single parsed CSV row from a sales import file.
class SalesImportRow {
  /// 1-based line number in the source file (header is line 1).
  final int lineNumber;
  final String? receiptNumber;
  final DateTime? date;
  final String paymentMethod;
  final String paymentStatus;
  final double? totalAmount;
  final double? cashReceived;
  final String? customerName;
  final String? referenceNumber;
  final String? notes;

  /// Validation error for this row, or `null` when the row can be imported.
  final String? error;

  const SalesImportRow({
    required this.lineNumber,
    this.receiptNumber,
    this.date,
    this.paymentMethod = 'Cash',
    this.paymentStatus = 'confirmed',
    this.totalAmount,
    this.cashReceived,
    this.customerName,
    this.referenceNumber,
    this.notes,
    this.error,
  });

  bool get isValid => error == null;
}

/// The result of parsing and validating a sales import file.
class SalesImportPreview {
  final String fileName;
  final List<SalesImportRow> rows;

  /// File-level problem (e.g. unreadable file or missing required columns).
  /// When set, [rows] is empty and nothing can be imported.
  final String? fileError;

  const SalesImportPreview({
    required this.fileName,
    required this.rows,
    this.fileError,
  });

  List<SalesImportRow> get validRows =>
      rows.where((r) => r.isValid).toList(growable: false);

  List<SalesImportRow> get invalidRows =>
      rows.where((r) => !r.isValid).toList(growable: false);
}

/// The outcome of a confirmed sales import.
class SalesImportResult {
  /// Rows inserted into `sales`.
  final int imported;

  /// Valid rows skipped because their receipt number already exists.
  final int skipped;

  /// Row-level failures during insert (line number -> message).
  final Map<int, String> errors;

  const SalesImportResult({
    required this.imported,
    required this.skipped,
    this.errors = const {},
  });
}

/// Owner-only sales-record import.
///
/// Sales import is a data-management operation, completely independent of
/// the staff reporting workflow: it never reads from or writes to
/// `export_history`, so an import can never produce a "My Report" record.
/// The only trace it leaves is an `import_sales` activity-log entry.
///
/// Expected CSV format (header row required, case-insensitive):
///
///     date,total,payment_method,payment_status,cash_received,
///     customer,reference,receipt_number,notes
///
/// Only `date` and `total` are required. `payment_method` defaults to
/// `Cash`, `payment_status` defaults to `confirmed`, and `cash_received`
/// defaults to the total. A missing `receipt_number` is generated with the
/// standard `YYYYMMDD-NNNN` sequence; an existing one that collides is
/// skipped as a duplicate.
class SalesImportService {
  final SaleRepository _saleRepository = SaleRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const int maxRows = 5000;

  static const List<String> _paymentMethods = ['Cash', 'GCash', 'Card', 'Other'];
  static const List<String> _paymentStatuses = [
    'confirmed',
    'cancelled',
    'refunded',
  ];

  /// Parses and validates [bytes] as a sales CSV without writing anything.
  ///
  /// Throws [AuthorizationException] when the current user lacks the
  /// Owner-only `import_sales` permission. Returns `null` on web, where the
  /// local sales database is unavailable.
  Future<SalesImportPreview?> previewSalesImport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!_sessionManager.hasPermission('import_sales')) {
      throw AuthorizationException('import_sales');
    }
    if (kIsWeb) return null;

    if (bytes.isEmpty) {
      return SalesImportPreview(
        fileName: fileName,
        rows: const [],
        fileError: 'The selected file is empty.',
      );
    }

    final List<List<dynamic>> table;
    try {
      var content = String.fromCharCodes(bytes);
      if (content.startsWith(String.fromCharCode(0xFEFF))) {
        content = content.substring(1);
      }
      // The csv package does not auto-detect row endings — normalise CRLF/CR
      // to LF and pass an explicit eol so rows split correctly.
      content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      table = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(content);
    } catch (_) {
      return SalesImportPreview(
        fileName: fileName,
        rows: const [],
        fileError: 'The file could not be read as CSV.',
      );
    }

    // Drop leading blank rows, then require a header row.
    final nonEmpty = table
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .toList();
    if (nonEmpty.isEmpty) {
      return SalesImportPreview(
        fileName: fileName,
        rows: const [],
        fileError: 'The file contains no data rows.',
      );
    }

    final header = nonEmpty.first.map((c) => _normHeader('$c')).toList();
    final columns = _mapColumns(header);
    if (!columns.containsKey(_Col.date) ||
        !columns.containsKey(_Col.total)) {
      return SalesImportPreview(
        fileName: fileName,
        rows: const [],
        fileError:
            'Missing required columns. The file must include a header row '
            'with at least "date" and "total".',
      );
    }

    final dataRows = nonEmpty.skip(1).toList();
    if (dataRows.length > maxRows) {
      return SalesImportPreview(
        fileName: fileName,
        rows: const [],
        fileError: 'Too many rows. A single import supports up to '
            '$maxRows sales records.',
      );
    }

    final rows = <SalesImportRow>[];
    for (var i = 0; i < dataRows.length; i++) {
      rows.add(_parseRow(dataRows[i], columns, i + 2));
    }

    return SalesImportPreview(fileName: fileName, rows: rows);
  }

  /// Inserts every valid row in [preview] as a sale record owned by the
  /// current user, inside a single transaction.
  ///
  /// Rows keep their historical `created_at` date and do not deduct stock —
  /// they are records of past sales, not new POS transactions. Rows whose
  /// supplied receipt number collides with an existing one are skipped.
  ///
  /// Throws [AuthorizationException] when the current user lacks the
  /// Owner-only `import_sales` permission.
  Future<SalesImportResult> importSales(SalesImportPreview preview) async {
    if (!_sessionManager.hasPermission('import_sales')) {
      throw AuthorizationException('import_sales');
    }
    final userId = _sessionManager.currentUser?.id;
    if (userId == null) {
      throw AuthorizationException('import_sales');
    }

    final valid = preview.validRows;
    if (valid.isEmpty) {
      return const SalesImportResult(imported: 0, skipped: 0);
    }

    var imported = 0;
    var skipped = 0;
    final errors = <int, String>{};

    await _dbHelper.transaction((txn) async {
      for (final row in valid) {
        final receipt = row.receiptNumber;
        final sale = Sale(
          totalAmount: row.totalAmount!,
          cashReceived: row.cashReceived ?? row.totalAmount!,
          change:
              (row.cashReceived ?? row.totalAmount!) - row.totalAmount!,
          paymentMethod: row.paymentMethod,
          paymentStatus: row.paymentStatus,
          referenceNumber: row.referenceNumber,
          customerName: row.customerName,
          userId: userId,
          createdAt: row.date!,
          receiptNumber: receipt,
          notes: row.notes,
        );

        try {
          if (receipt != null && receipt.isNotEmpty) {
            await _saleRepository.insert(sale, txn: txn);
          } else {
            final generated =
                await _saleRepository.nextReceiptNumber(row.date!, txn: txn);
            await _saleRepository.insert(
              sale.copyWith(receiptNumber: generated),
              txn: txn,
            );
          }
          imported++;
        } on DatabaseException catch (e) {
          if (e.isUniqueConstraintError()) {
            skipped++;
          } else {
            errors[row.lineNumber] = 'Database error';
          }
        } catch (_) {
          errors[row.lineNumber] = 'Import failed';
        }
      }
    });

    await _activityLogService.logActivity(
      action: 'import_sales',
      entity: 'sale',
      details:
          'Imported $imported sale record(s) from ${preview.fileName} '
          '($skipped skipped, ${errors.length} failed)',
    );

    return SalesImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }

  // ── Parsing helpers ──────────────────────────────────────────────────

  String _normHeader(String header) {
    return header
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9#]'), '');
  }

  Map<_Col, int> _mapColumns(List<String> header) {
    const mapping = <String, _Col>{
      'receiptnumber': _Col.receipt,
      'receipt#': _Col.receipt,
      'receipt': _Col.receipt,
      'receiptno': _Col.receipt,
      'date': _Col.date,
      'datetime': _Col.date,
      'createdat': _Col.date,
      'created': _Col.date,
      'total': _Col.total,
      'totalamount': _Col.total,
      'amount': _Col.total,
      'paymentmethod': _Col.method,
      'method': _Col.method,
      'paymentstatus': _Col.status,
      'status': _Col.status,
      'cashreceived': _Col.cash,
      'cash': _Col.cash,
      'customer': _Col.customer,
      'customername': _Col.customer,
      'reference': _Col.reference,
      'referencenumber': _Col.reference,
      'ref': _Col.reference,
      'notes': _Col.notes,
      'note': _Col.notes,
    };

    final columns = <_Col, int>{};
    for (var i = 0; i < header.length; i++) {
      final col = mapping[header[i]];
      if (col != null && !columns.containsKey(col)) {
        columns[col] = i;
      }
    }
    return columns;
  }

  String _cell(List<dynamic> row, Map<_Col, int> columns, _Col col) {
    final index = columns[col];
    if (index == null || index >= row.length) return '';
    return row[index].toString().trim();
  }

  SalesImportRow _parseRow(
    List<dynamic> cells,
    Map<_Col, int> columns,
    int lineNumber,
  ) {
    final dateText = _cell(cells, columns, _Col.date);
    final totalText = _cell(cells, columns, _Col.total);
    final methodText = _cell(cells, columns, _Col.method);
    final statusText = _cell(cells, columns, _Col.status);
    final cashText = _cell(cells, columns, _Col.cash);
    final customer = _cell(cells, columns, _Col.customer);
    final reference = _cell(cells, columns, _Col.reference);
    final receipt = _cell(cells, columns, _Col.receipt);
    final notes = _cell(cells, columns, _Col.notes);

    final date = _parseDate(dateText);
    if (date == null) {
      return SalesImportRow(
        lineNumber: lineNumber,
        error: 'Invalid or missing date',
      );
    }

    final total = _parseAmount(totalText);
    if (total == null || total <= 0) {
      return SalesImportRow(
        lineNumber: lineNumber,
        date: date,
        error: 'Invalid or missing total amount',
      );
    }

    String method = 'Cash';
    if (methodText.isNotEmpty) {
      final match = _paymentMethods.where(
        (m) => m.toLowerCase() == methodText.toLowerCase(),
      );
      if (match.isEmpty) {
        return SalesImportRow(
          lineNumber: lineNumber,
          date: date,
          totalAmount: total,
          error: 'Unknown payment method "$methodText"',
        );
      }
      method = match.first;
    }

    String status = 'confirmed';
    if (statusText.isNotEmpty) {
      final match = _paymentStatuses.where(
        (s) => s == statusText.toLowerCase(),
      );
      if (match.isEmpty) {
        return SalesImportRow(
          lineNumber: lineNumber,
          date: date,
          totalAmount: total,
          paymentMethod: method,
          error: 'Unknown payment status "$statusText"',
        );
      }
      status = match.first;
    }

    double? cash;
    if (cashText.isNotEmpty) {
      cash = _parseAmount(cashText);
      if (cash == null || cash < 0) {
        return SalesImportRow(
          lineNumber: lineNumber,
          date: date,
          totalAmount: total,
          paymentMethod: method,
          paymentStatus: status,
          error: 'Invalid cash received amount',
        );
      }
      if (method == 'Cash' && cash < total) {
        return SalesImportRow(
          lineNumber: lineNumber,
          date: date,
          totalAmount: total,
          paymentMethod: method,
          paymentStatus: status,
          error: 'Cash received is less than the total',
        );
      }
    }

    return SalesImportRow(
      lineNumber: lineNumber,
      receiptNumber: receipt.isEmpty ? null : receipt,
      date: date,
      paymentMethod: method,
      paymentStatus: status,
      totalAmount: total,
      cashReceived: cash,
      customerName: customer.isEmpty ? null : customer,
      referenceNumber: reference.isEmpty ? null : reference,
      notes: notes.isEmpty ? null : notes,
    );
  }

  DateTime? _parseDate(String text) {
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    for (final pattern in const [
      'yyyy-MM-dd h:mm a',
      'yyyy-MM-dd HH:mm',
      'MM/dd/yyyy h:mm a',
      'MM/dd/yyyy HH:mm',
      'MM/dd/yyyy',
      'M/d/yyyy',
      'yyyy/MM/dd',
    ]) {
      try {
        return DateFormat(pattern).parse(text);
      } catch (_) {
        // Try the next format.
      }
    }
    return null;
  }

  double? _parseAmount(String text) {
    if (text.isEmpty) return null;
    final cleaned = text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned);
  }
}

enum _Col { receipt, date, total, method, status, cash, customer, reference, notes }
