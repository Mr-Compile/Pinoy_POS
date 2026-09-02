import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/calendar_day_sales.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';

/// Single source of truth for sales analytics, reports, and exports.
///
/// All methods enforce:
/// - `view_reports` / `view_sales` permission checks.
/// - confirmed-only sales (`payment_status = 'confirmed'`).
/// - non-deleted sales (`deleted_at IS NULL`).
/// - Staff are automatically scoped to `user_id = currentUser.id`.
class SalesAnalyticsService {
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final SessionManager _sessionManager = SessionManager();

  int? get _scopedUserId {
    final user = _sessionManager.currentUser;
    if (user == null) return null;
    return user.role == UserRole.staff ? user.id : null;
  }

  bool get _canViewReports => _sessionManager.hasPermission('view_reports');
  bool get _canViewSales => _sessionManager.hasPermission('view_sales');

  /// Complete analytics for the selected [period].
  Future<SalesAnalytics> getAnalytics(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_canViewReports) return _emptyAnalytics(period, customStart, customEnd);

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    return _analyticsForBounds(bounds);
  }

  /// Complete analytics for explicit [bounds].
  Future<SalesAnalytics> getAnalyticsForBounds(
    ReportingPeriodBounds bounds,
  ) async {
    if (!_canViewReports) return SalesAnalytics.empty(bounds);
    return _analyticsForBounds(bounds);
  }

  /// Sales list for a period, newest first.
  Future<List<Sale>> getSalesList(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
    String? paymentMethod,
    String? search,
    int limit = 500,
  }) async {
    if (!_canViewSales) return [];

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );

    final userId = _scopedUserId;
    return _saleRepository.getConfirmedSalesForRange(
      bounds.start,
      bounds.end,
      userId: userId,
      paymentMethod: paymentMethod,
      search: search,
      limit: limit,
    );
  }

  /// Sales list for a custom date range.
  Future<List<Sale>> getSalesListForRange(
    DateTime start,
    DateTime end, {
    String? paymentMethod,
    String? search,
    int limit = 500,
  }) async {
    if (!_canViewSales) return [];

    return _saleRepository.getConfirmedSalesForRange(
      start,
      end,
      userId: _scopedUserId,
      paymentMethod: paymentMethod,
      search: search,
      limit: limit,
    );
  }

  /// Per-day sales totals for a calendar month.
  Future<List<CalendarDaySales>> getCalendarDaySales(
    DateTime monthStart,
  ) async {
    if (!_canViewReports) return [];

    final start = DateTime(monthStart.year, monthStart.month, 1);
    final end = DateTime(monthStart.year, monthStart.month + 1, 1);

    return _saleRepository.getCalendarDaySales(
      start,
      end,
      userId: _scopedUserId,
    );
  }

  /// Calendar data for an explicit range.
  Future<List<CalendarDaySales>> getCalendarDaySalesForRange(
    DateTime start,
    DateTime end,
  ) async {
    if (!_canViewReports) return [];

    return _saleRepository.getCalendarDaySales(
      start,
      end,
      userId: _scopedUserId,
    );
  }

  Future<SalesAnalytics> _analyticsForBounds(
    ReportingPeriodBounds bounds,
  ) async {
    final userId = _scopedUserId;

    final currentSummary = await _saleRepository.getSalesSummary(
      bounds.start,
      bounds.end,
      userId: userId,
    );
    final currentItemsSold = await _saleRepository.getItemsSold(
      bounds.start,
      bounds.end,
      userId: userId,
    );

    final previousSummary = await _saleRepository.getSalesSummary(
      bounds.previousStart,
      bounds.previousEnd,
      userId: userId,
    );
    final previousItemsSold = await _saleRepository.getItemsSold(
      bounds.previousStart,
      bounds.previousEnd,
      userId: userId,
    );

    final totalSales = (currentSummary['total_sales'] as num).toDouble();
    final transactionCount = (currentSummary['transaction_count'] as num).toInt();
    final averageTransaction =
        transactionCount == 0 ? 0.0 : totalSales / transactionCount;

    final previousTotal = (previousSummary['total_sales'] as num).toDouble();
    final previousCount =
        (previousSummary['transaction_count'] as num).toInt();
    final previousAverage =
        previousCount == 0 ? 0.0 : previousTotal / previousCount;

    final comparison = SalesPeriodComparison(
      previousTotalSales: previousTotal,
      previousTransactionCount: previousCount,
      previousAverageTransaction: previousAverage,
      previousItemsSold: previousItemsSold,
    );

    final rawTrend = await _saleRepository.getSalesTrend(
      bounds.start,
      bounds.end,
      groupBy: bounds.groupBy,
      userId: userId,
    );
    final trend = _fillTrendGaps(rawTrend, bounds);

    final paymentBreakdown = await _saleRepository.getPaymentBreakdown(
      bounds.start,
      bounds.end,
      userId: userId,
    );

    final topProductRows = await _saleItemRepository.getTopProducts(
      since: bounds.start,
      until: bounds.end,
      userId: userId,
      limit: 10,
      sortByRevenue: false,
    );
    final topProducts = topProductRows.map(TopProductResult.fromMap).toList();

    final staffSummaries = userId == null
        ? await _saleRepository.getStaffSalesSummary(
            bounds.start,
            bounds.end,
            role: UserRole.staff,
          )
        : <StaffSalesSummary>[];

    final sales = await _saleRepository.getConfirmedSalesForRange(
      bounds.start,
      bounds.end,
      userId: userId,
      limit: 100,
    );

    return SalesAnalytics(
      bounds: bounds,
      totalSales: totalSales,
      transactionCount: transactionCount,
      averageTransaction: averageTransaction,
      itemsSold: currentItemsSold,
      comparison: comparison,
      trend: trend,
      paymentBreakdown: paymentBreakdown,
      topProducts: topProducts,
      staffSummaries: staffSummaries,
      sales: sales,
    );
  }

  SalesAnalytics _emptyAnalytics(
    ReportingPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    return SalesAnalytics.empty(bounds);
  }

  List<DailySalesPoint> _fillTrendGaps(
    List<DailySalesPoint> points,
    ReportingPeriodBounds bounds,
  ) {
    final map = <DateTime, DailySalesPoint>{};
    for (final p in points) {
      map[_trendKey(p.date, bounds.groupBy)] = p;
    }

    final filled = <DailySalesPoint>[];
    var cursor = bounds.start;
    final end = bounds.end;

    while (cursor.isBefore(end)) {
      final key = _trendKey(cursor, bounds.groupBy);
      final existing = map[key];
      if (existing != null) {
        filled.add(existing);
      } else {
        filled.add(DailySalesPoint(date: cursor, total: 0.0, count: 0));
      }
      cursor = _nextTrendStep(cursor, bounds.groupBy);
    }

    return filled;
  }

  DateTime _trendKey(DateTime date, ReportGroupBy groupBy) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        return DateTime(date.year, date.month, date.day, date.hour);
      case ReportGroupBy.day:
      case ReportGroupBy.week:
        return DateTime(date.year, date.month, date.day);
      case ReportGroupBy.month:
        return DateTime(date.year, date.month, 1);
    }
  }

  DateTime _nextTrendStep(DateTime date, ReportGroupBy groupBy) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        return date.add(const Duration(hours: 1));
      case ReportGroupBy.day:
      case ReportGroupBy.week:
        return date.add(const Duration(days: 1));
      case ReportGroupBy.month:
        final next = DateTime(date.year, date.month + 1, 1);
        return next;
    }
  }

  /// Staff performance for the given period.
  Future<List<StaffSalesSummary>> getStaffPerformance(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_canViewReports) return [];

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );

    final user = _sessionManager.currentUser;
    if (user?.role == UserRole.staff) {
      // Staff cannot view other staff performance.
      return [];
    }

    return _saleRepository.getStaffSalesSummary(
      bounds.start,
      bounds.end,
      role: UserRole.staff,
    );
  }

  /// Payment breakdown for the given period.
  Future<List<PaymentBreakdown>> getPaymentBreakdown(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_canViewReports) return [];

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    return _saleRepository.getPaymentBreakdown(
      bounds.start,
      bounds.end,
      userId: _scopedUserId,
    );
  }

  /// Total confirmed sales for the current user today (used by legacy callers).
  Future<double> getTodaySales() async {
    if (!_canViewReports && !_canViewSales) return 0.0;
    final bounds = periodBoundsFor(ReportingPeriod.today);
    final summary = await _saleRepository.getSalesSummary(
      bounds.start,
      bounds.end,
      userId: _scopedUserId,
    );
    return (summary['total_sales'] as num).toDouble();
  }

  /// Total confirmed sales for the current month (used by legacy callers).
  Future<double> getMonthSales() async {
    if (!_canViewReports && !_canViewSales) return 0.0;
    final bounds = periodBoundsFor(ReportingPeriod.thisMonth);
    final summary = await _saleRepository.getSalesSummary(
      bounds.start,
      bounds.end,
      userId: _scopedUserId,
    );
    return (summary['total_sales'] as num).toDouble();
  }

  /// Confirmed sales for a date range.
  Future<List<Sale>> getSalesByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    if (!_canViewReports && !_canViewSales) return [];
    return _saleRepository.getConfirmedSalesForRange(
      start,
      end,
      userId: _scopedUserId,
    );
  }
}
