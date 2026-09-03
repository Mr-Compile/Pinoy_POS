import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/export_history.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/export_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

/// Business intelligence service for reports and exports.
///
/// This is the single service the reports UI uses; it in turn delegates to
/// repositories and DAOs, keeping the SQL behind the approved architecture.
class ReportService {
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final ProductRepository _productRepository = ProductRepository();
  final UserRepository _userRepository = UserRepository();
  final ExportHistoryRepository _exportHistoryRepository =
      ExportHistoryRepository();
  final SalesService _salesService = SalesService();
  final SettingsService _settingsService = SettingsService();
  final NotificationService _notificationService = NotificationService();
  final SessionManager _sessionManager = SessionManager();

  // ── Business metrics (Owner / Staff) ──

  /// Today’s confirmed sales total.  Delegated to [SalesService].
  Future<double> getTodaySales() async {
    if (!_sessionManager.hasPermission('view_reports')) return 0.0;
    return _salesService.getTodaySales();
  }

  /// This month’s confirmed sales total.  Delegated to [SalesService].
  Future<double> getMonthSales() async {
    if (!_sessionManager.hasPermission('view_reports')) return 0.0;
    return _salesService.getMonthSales();
  }

  Future<int> getLowStockCount() async {
    if (!_sessionManager.hasPermission('view_reports')) {
      return 0;
    }
    final products = await _productRepository.getLowStockProducts();
    return products.length;
  }

  Future<int> getTotalProducts() async {
    if (!_sessionManager.hasPermission('view_reports')) {
      return 0;
    }
    final products = await _productRepository.getActiveProducts();
    return products.length;
  }

  /// Returns total active (non-voided) sales for the authenticated role.
  ///
  /// Only [Sale.paymentStatus] == 'confirmed' sales are counted; pending,
  /// cancelled, and refunded sales are excluded from the total.
  Future<int> getTotalTransactions() async {
    if (!_sessionManager.hasPermission('view_reports')) return 0;

    final userId = _sessionManager.currentUser?.role == UserRole.staff
        ? _sessionManager.currentUser!.id
        : null;

    final sales = await _saleRepository.getFilteredSales(
      paymentStatus: 'confirmed',
      userId: userId,
      limit: 99999,
    );
    return sales.length;
  }

  /// Returns the confirmed sales for a date range.  Delegated to [SalesService].
  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async {
    if (!_sessionManager.hasPermission('view_reports')) return [];
    return _salesService.getSalesByDateRange(start, end);
  }

  /// Returns the aggregated total per payment method for the given date
  /// range.  Staff results are scoped to the current user's sales.
  Future<List<PaymentBreakdown>> getPaymentBreakdown(
    DateTime start,
    DateTime end,
  ) async {
    if (!_sessionManager.hasPermission('view_reports')) return [];

    final sales = await getSalesByDateRange(start, end);
    final totals = <String, double>{};
    final counts = <String, int>{};

    for (final sale in sales) {
      if (sale.paymentStatus != 'confirmed') continue;
      final method = sale.paymentMethod;
      totals[method] = (totals[method] ?? 0.0) + sale.totalAmount;
      counts[method] = (counts[method] ?? 0) + 1;
    }

    return totals.entries
        .map((e) => PaymentBreakdown(
              method: e.key,
              total: e.value,
              count: counts[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Returns the top-selling products by quantity for the given date range.
  Future<List<TopProductResult>> getTopProducts(
    DateTime start,
    DateTime end, {
    int limit = 5,
  }) async {
    if (!_sessionManager.hasPermission('view_reports')) return [];

    final userId = _sessionManager.currentUser?.role == UserRole.staff
        ? _sessionManager.currentUser!.id
        : null;

    return _saleItemRepository
        .getTopProducts(
          since: start,
          until: end,
          userId: userId,
          limit: limit,
        )
        .then((rows) => rows.map(TopProductResult.fromMap).toList());
  }

  /// Returns a per-day sales summary for the given date range.
  Future<List<DailySalesPoint>> getDailySales(
    DateTime start,
    DateTime end,
  ) async {
    if (!_sessionManager.hasPermission('view_reports')) return [];

    final sales = await getSalesByDateRange(start, end);
    final map = <DateTime, DailySalesPoint>{};

    for (final sale in sales) {
      if (sale.paymentStatus != 'confirmed') continue;
      final day = DateTime(
        sale.createdAt.year,
        sale.createdAt.month,
        sale.createdAt.day,
      );
      final existing = map[day];
      if (existing == null) {
        map[day] = DailySalesPoint(
          date: day,
          total: sale.totalAmount,
          count: 1,
        );
      } else {
        map[day] = DailySalesPoint(
          date: day,
          total: existing.total + sale.totalAmount,
          count: existing.count + 1,
        );
      }
    }

    return map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Returns the store information (name, address, contact, currency) to use
  /// in reports and exports.  Delegated to [SettingsService].
  Future<Settings> getStoreInfo() => _settingsService.getStoreInfo();

  /// Returns true when store information is missing or has the default name.
  /// Delegated to [SettingsService].
  Future<bool> isStoreInfoIncomplete() => _settingsService.isStoreInfoIncomplete();

  // ── System metrics (System Admin) ──

  Future<int> getTotalUsers() async {
    if (!_sessionManager.hasPermission('manage_users')) {
      return 0;
    }
    final users = await _userRepository.getAllActive();
    return users.length;
  }

  Future<int> getActiveUsers() async {
    if (!_sessionManager.hasPermission('manage_users')) {
      return 0;
    }
    final users = await _userRepository.getActiveUsers();
    return users.length;
  }

  /// Returns the path to the most recent backup file, or null if none exists.
  Future<String?> getLastBackupPath() async {
    if (!_sessionManager.hasPermission('backup_restore')) {
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = Directory(dir.path)
          .listSync()
          .where((f) => f.path.endsWith('.db') && f.path.contains('backup'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) return null;
      return files.first.path;
    } catch (_) {
      return null;
    }
  }

  /// Returns the last backup date, or null if no backup exists.
  Future<DateTime?> getLastBackupDate() async {
    final path = await getLastBackupPath();
    if (path == null) return null;
    try {
      final stat = await File(path).stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  }

  /// Records an export in the `export_history` table and returns the new
  /// row id. Called by the Reports UI after a file has been written to disk.
  ///
  /// Recording is best-effort: a failure here does not invalidate a
  /// successful export, but it now returns `null` so callers can tell.
  Future<int?> recordExport({
    required String fileFormat,
    required String filePath,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
    int? fileSize,
    String? thumbnailPath,
    String? reportNumber,
  }) async {
    if (!_sessionManager.hasPermission('export_reports')) {
      return null;
    }
    try {
      return await _exportHistoryRepository.insert(ExportHistory(
        reportType: 'sales',
        fileFormat: fileFormat,
        filePath: filePath,
        dateRangeStart: dateRangeStart,
        dateRangeEnd: dateRangeEnd,
        createdBy: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
        status: ReportStatus.generated,
        fileSize: fileSize,
        thumbnailPath: thumbnailPath,
        reportNumber: reportNumber,
      ));
    } catch (_) {
      return null;
    }
  }

  /// Marks a previously generated report as submitted to the Owner and
  /// notifies all Owner accounts.
  Future<bool> submitReport(int id) async {
    if (!_sessionManager.hasPermission('export_reports')) return false;

    final report = await _exportHistoryRepository.getById(id);
    if (report == null) return false;

    await _exportHistoryRepository.update(
      report.copyWith(
        status: ReportStatus.submitted,
        submittedAt: DateTime.now(),
      ),
    );

    await _notifyOwnersOfSubmission(report);
    return true;
  }

  Future<void> _notifyOwnersOfSubmission(ExportHistory report) async {
    try {
      final owners = await _userRepository.getByRole(UserRole.owner);
      final ownerIds =
          owners.where((u) => u.id != null).map((u) => u.id!).toList();
      if (ownerIds.isEmpty) return;

      final reportNumber = report.reportNumber ?? 'RPT-${report.id}';
      final submitter = _sessionManager.currentUser;
      final submitterName = submitter?.fullName ?? 'A staff member';

      await _notificationService.createNotificationForUsers(
        title: 'Report Submitted',
        message:
            '$submitterName submitted sales report $reportNumber for review.',
        type: 'report_submitted',
        userIds: ownerIds,
      );
    } catch (_) {
      // Notification is best-effort and must not block the submission.
    }
  }

  /// Marks a submitted report as viewed by the Owner.
  Future<bool> markReportViewed(int id) async {
    if (!_sessionManager.hasPermission('view_report_submissions')) return false;

    final report = await _exportHistoryRepository.getById(id);
    if (report == null) return false;

    await _exportHistoryRepository.update(
      report.copyWith(
        status: ReportStatus.viewed,
        viewedAt: DateTime.now(),
      ),
    );
    return true;
  }

  /// Archives a report (soft delete).
  Future<bool> archiveReport(int id) async {
    final report = await _exportHistoryRepository.getById(id);
    if (report == null) return false;

    final currentUser = _sessionManager.currentUser;
    final canArchive = _sessionManager.hasPermission('view_report_submissions') ||
        report.createdBy == currentUser?.id;
    if (!canArchive) return false;

    await _exportHistoryRepository.update(
      report.copyWith(status: ReportStatus.archived),
    );
    return true;
  }

  /// Returns a single report by id if the current user is allowed to see it.
  Future<ExportHistory?> getReportById(int id) async {
    final report = await _exportHistoryRepository.getById(id);
    if (report == null) return null;

    if (report.deletedAt != null) return null;

    if (_sessionManager.hasPermission('view_report_submissions')) {
      return report;
    }

    final currentUser = _sessionManager.currentUser;
    if (report.createdBy == currentUser?.id) return report;

    return null;
  }

  /// Returns reports submitted to the Owner (staff submissions).
  Future<List<ExportHistory>> getSubmittedReports() async {
    if (!_sessionManager.hasPermission('view_report_submissions')) return [];
    return _exportHistoryRepository.getSubmittedToOwner();
  }

  /// Returns the full name of the user who created a report, if the
  /// current user is allowed to see staff details.
  Future<String?> getReportCreatorName(int userId) async {
    if (!_sessionManager.hasPermission('view_staff_performance') &&
        !_sessionManager.hasPermission('manage_staff')) {
      return null;
    }
    final user = await _userRepository.getById(userId);
    return user?.fullName;
  }

  /// Returns reports generated by the current user.
  Future<List<ExportHistory>> getMyReports() async {
    final user = _sessionManager.currentUser;
    if (user?.id == null) return [];
    return _exportHistoryRepository.getByCreatedBy(user!.id!);
  }

  /// Imports an externally provided report file into the app reports
  /// directory and records it in `export_history`.
  ///
  /// Returns the new [ExportHistory] row, or `null` if the user is not
  /// allowed to import or the file cannot be persisted.
  Future<ExportHistory?> importReport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (kIsWeb) return null;
    if (!_sessionManager.hasPermission('export_reports')) return null;

    final user = _sessionManager.currentUser;
    if (user?.id == null) return null;

    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final fileFormat = switch (ext) {
      'pdf' => 'pdf',
      'xlsx' || 'xls' => 'excel',
      'csv' => 'csv',
      _ => 'unknown',
    };
    if (fileFormat == 'unknown') return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory(p.join(appDir.path, 'reports'));
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      final reportNumber = await nextReportNumber();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName =
          'imported_${reportNumber}_$timestamp.$ext';
      final storedPath = p.join('reports', safeName);
      final file = File(p.join(appDir.path, storedPath));
      await file.writeAsBytes(bytes, flush: true);

      final id = await _exportHistoryRepository.insert(ExportHistory(
        reportType: 'sales',
        fileFormat: fileFormat,
        filePath: storedPath,
        createdBy: user!.id,
        createdAt: DateTime.now(),
        status: ReportStatus.imported,
        fileSize: bytes.length,
        reportNumber: reportNumber,
      ));

      final saved = await _exportHistoryRepository.getById(id);
      return saved;
    } catch (e, st) {
      debugPrint('[ReportService] importReport failed: $e\n$st');
      return null;
    }
  }

  /// Returns a readable report number for the next report.
  Future<String> nextReportNumber() async {
    final now = DateTime.now();
    final prefix = 'RPT';
    final timestamp = now.millisecondsSinceEpoch;
    return '$prefix-$timestamp';
  }

  /// Refreshes the cached store info, used after settings are updated.
  /// Delegated to [SettingsService].
  Future<void> refreshStoreInfo() => _settingsService.refreshStoreInfo();
}
