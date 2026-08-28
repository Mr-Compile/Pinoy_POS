import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/export_history.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/export_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

/// Payment method totals used in reports and analytics.
class PaymentBreakdown {
  final String method;
  final double total;
  final int count;

  PaymentBreakdown({
    required this.method,
    required this.total,
    required this.count,
  });
}

/// A simple daily sales point for trend charts and date-range reports.
class DailySalesPoint {
  final DateTime date;
  final double total;
  final int count;

  DailySalesPoint({
    required this.date,
    required this.total,
    required this.count,
  });
}

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
  final SettingsRepository _settingsRepository = SettingsRepository();
  final SessionManager _sessionManager = SessionManager();

  Settings? _cachedSettings;

  // ── Business metrics (Owner / Staff) ──

  Future<double> getTodaySales() async {
    if (!_sessionManager.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    // Staff: only own sales
    if (_sessionManager.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForDateForUser(
        now,
        _sessionManager.currentUser!.id!,
      );
    }
    return _saleRepository.getTotalSalesForDate(now);
  }

  Future<double> getMonthSales() async {
    if (!_sessionManager.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    if (_sessionManager.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForMonthForUser(
        now.year,
        now.month,
        _sessionManager.currentUser!.id!,
      );
    }
    return _saleRepository.getTotalSalesForMonth(now.year, now.month);
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

  /// Returns the sales for a date range.  For Staff the results are
  /// filtered to the current user's own sales. Cancelled/refunded sales
  /// are excluded from reporting views.
  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async {
    if (!_sessionManager.hasPermission('view_reports')) return [];

    final userId = _sessionManager.currentUser?.role == UserRole.staff
        ? _sessionManager.currentUser!.id
        : null;

    return _saleRepository.getFilteredSales(
      start: start,
      end: end,
      userId: userId,
      limit: 500,
    );
  }

  /// Returns all non-voided sales for the authenticated role.
  Future<List<Sale>> getAllSales() async {
    if (!_sessionManager.hasPermission('view_reports')) return [];

    if (_sessionManager.currentUser?.role == UserRole.staff) {
      return _saleRepository
          .getByUserId(_sessionManager.currentUser!.id!, limit: 500);
    }

    return _saleRepository.getAllActive(limit: 500);
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
        .getTopProductsByQuantity(
          since: start,
          userId: userId,
          limit: limit,
        )
        .then((rows) => rows
            .map((r) => TopProductResult(
                  productId: r['product_id'] as int,
                  productName: r['product_name'] as String,
                  totalQuantity: r['total_quantity'] as int,
                ))
            .toList());
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
  /// in reports and exports.  If none is configured, a default is returned.
  Future<Settings> getStoreInfo() async {
    _cachedSettings ??= await _settingsRepository.getSettings();
    return _cachedSettings ??
        Settings(
          storeName: 'Pinoy POS',
          currency: 'PHP',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
  }

  /// Returns true when store information is missing or has the default name.
  /// Used to show setup guidance on the reports screen.
  Future<bool> isStoreInfoIncomplete() async {
    final info = await getStoreInfo();
    return info.storeName.trim().isEmpty ||
        info.storeName.trim().toLowerCase() == 'my store' ||
        info.storeName.trim().toLowerCase() == 'pinoy pos';
  }

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

  /// Records an export in the `export_history` table.
  ///
  /// Called by the Reports UI after a CSV/PDF file has actually been
  /// written to disk. The UI never touches the repository directly; this
  /// keeps the data-access layer behind the service. Recording is
  /// best-effort: a failure here does not invalidate a successful export.
  Future<void> recordExport({
    required String fileFormat,
    required String filePath,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
  }) async {
    if (!_sessionManager.hasPermission('export_reports')) {
      return;
    }
    try {
      await _exportHistoryRepository.insert(ExportHistory(
        reportType: 'sales',
        fileFormat: fileFormat,
        filePath: filePath,
        dateRangeStart: dateRangeStart,
        dateRangeEnd: dateRangeEnd,
        createdBy: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
      ));
    } catch (_) {
      // Best-effort: don't fail the export if history recording fails.
    }
  }

  /// Refreshes the cached store info, used after settings are updated.
  Future<void> refreshStoreInfo() async {
    _cachedSettings = null;
    await getStoreInfo();
  }
}

/// A top-selling product result returned by [ReportService.getTopProducts].
class TopProductResult {
  final int productId;
  final String productName;
  final int totalQuantity;

  TopProductResult({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
  });
}
