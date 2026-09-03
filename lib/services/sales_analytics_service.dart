import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/calendar_day_sales.dart';
import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/peak_sales_period.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/sales_by_hour_point.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

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
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();

  int? get _scopedUserId {
    final user = _sessionManager.currentUser;
    if (user == null) return null;
    return user.role == UserRole.staff ? user.id : null;
  }

  bool get _canViewReports => _sessionManager.hasPermission('view_reports');
  bool get _canViewSales => _sessionManager.hasPermission('view_sales');
  bool get _canViewStaffPerformance =>
      _sessionManager.hasPermission('view_staff_performance');

  /// Complete analytics for the selected [period].
  Future<SalesAnalytics> getAnalytics(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
    String? paymentMethod,
    String? paymentStatus,
    int? selectedStaffId,
  }) async {
    if (!_canViewReports) return _emptyAnalytics(period, customStart, customEnd);

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    return _analyticsForBounds(
      bounds,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      selectedStaffId: selectedStaffId,
    );
  }

  /// Complete analytics for explicit [bounds].
  Future<SalesAnalytics> getAnalyticsForBounds(
    ReportingPeriodBounds bounds,
  ) async {
    if (!_canViewReports) return SalesAnalytics.empty(bounds);
    return _analyticsForBounds(bounds);
  }

  /// Complete analytics for a single staff member over the selected [period].
  ///
  /// Staff members can only view their own analytics; the [staffUserId] is
  /// silently coerced to the current user for that role. Admins and owners
  /// may view any staff member's analytics.
  Future<SalesAnalytics> getStaffDetailAnalytics(
    int staffUserId,
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
    String? paymentMethod,
    String? paymentStatus,
  }) async {
    if (!_canViewReports) {
      return _emptyAnalytics(period, customStart, customEnd);
    }

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );

    final user = _sessionManager.currentUser;
    final effectiveUserId = user?.role == UserRole.staff ? user?.id : staffUserId;
    if (effectiveUserId == null) {
      return _emptyAnalytics(period, customStart, customEnd);
    }

    return _analyticsForBounds(
      bounds,
      targetUserId: effectiveUserId,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
    );
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
    ReportingPeriodBounds bounds, {
    int? targetUserId,
    String? paymentMethod,
    String? paymentStatus,
    int? selectedStaffId,
  }) async {
    final useFiltered = (paymentMethod != null && paymentMethod.isNotEmpty) ||
        (paymentStatus != null && paymentStatus != 'confirmed') ||
        (selectedStaffId != null);
    if (useFiltered) {
      return _filteredAnalyticsForBounds(
        bounds,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        userId: selectedStaffId ?? targetUserId ?? _scopedUserId,
      );
    }

    final userId = selectedStaffId ?? targetUserId ?? _scopedUserId;

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

    final rawPreviousTrend = await _saleRepository.getSalesTrend(
      bounds.previousStart,
      bounds.previousEnd,
      groupBy: bounds.groupBy,
      userId: userId,
    );
    final previousBounds = ReportingPeriodBounds(
      start: bounds.previousStart,
      end: bounds.previousEnd,
      previousStart: bounds.previousStart,
      previousEnd: bounds.previousEnd,
      groupBy: bounds.groupBy,
    );
    final previousTrend = _fillTrendGaps(rawPreviousTrend, previousBounds);

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
      sortByRevenue: true,
    );
    final topProducts = topProductRows.map(TopProductResult.fromMap).toList();

    final List<CategorySalesResult> categorySales =
        await _saleRepository.getCategorySales(
      bounds.start,
      bounds.end,
      userId: userId,
    );

    final staffSummaries = userId == null && _canViewStaffPerformance
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

    final peakSalesPeriod = await _computePeakSalesPeriod(
      rawTrend,
      bounds,
      userId: userId,
    );

    return SalesAnalytics(
      bounds: bounds,
      totalSales: totalSales,
      transactionCount: transactionCount,
      averageTransaction: averageTransaction,
      itemsSold: currentItemsSold,
      comparison: comparison,
      trend: trend,
      previousTrend: previousTrend,
      paymentBreakdown: paymentBreakdown,
      topProducts: topProducts,
      categorySales: categorySales,
      staffSummaries: staffSummaries,
      peakSalesPeriod: peakSalesPeriod,
      sales: sales,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      staffUserId: selectedStaffId ?? targetUserId,
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

  Future<SalesAnalytics> _filteredAnalyticsForBounds(
    ReportingPeriodBounds bounds, {
    int? userId,
    String? paymentMethod,
    String? paymentStatus,
  }) async {
    final currentSales = await _saleRepository.getFilteredSales(
      start: bounds.start,
      end: bounds.end,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      userId: userId,
      limit: null,
    );

    final previousSales = await _saleRepository.getFilteredSales(
      start: bounds.previousStart,
      end: bounds.previousEnd,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      userId: userId,
      limit: null,
    );

    final sales = currentSales.take(100).toList();

    final currentSaleIds = currentSales
        .where((s) => s.id != null)
        .map((s) => s.id!)
        .toList();
    final currentItems = currentSaleIds.isEmpty
        ? <SaleItem>[]
        : await _saleItemRepository.getBySaleIds(currentSaleIds);

    final previousSaleIds = previousSales
        .where((s) => s.id != null)
        .map((s) => s.id!)
        .toList();
    final previousItems = previousSaleIds.isEmpty
        ? <SaleItem>[]
        : await _saleItemRepository.getBySaleIds(previousSaleIds);

    final transactionCount = currentSales.length;
    final totalSales = currentSales.fold<double>(
      0.0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final averageTransaction =
        transactionCount == 0 ? 0.0 : totalSales / transactionCount;
    final itemsSold = currentItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final previousCount = previousSales.length;
    final previousTotal = previousSales.fold<double>(
      0.0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final previousAverage =
        previousCount == 0 ? 0.0 : previousTotal / previousCount;
    final previousItemsSold = previousItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final comparison = SalesPeriodComparison(
      previousTotalSales: previousTotal,
      previousTransactionCount: previousCount,
      previousAverageTransaction: previousAverage,
      previousItemsSold: previousItemsSold,
    );

    final trend = _trendFromSales(currentSales, bounds);

    final previousBounds = ReportingPeriodBounds(
      start: bounds.previousStart,
      end: bounds.previousEnd,
      previousStart: bounds.previousStart,
      previousEnd: bounds.previousEnd,
      groupBy: bounds.groupBy,
    );
    final previousTrend = _trendFromSales(previousSales, previousBounds);

    final paymentBreakdown = _paymentBreakdownFromSales(currentSales);
    final topProducts = _topProductsFromItems(currentItems);
    final categorySales =
        await _categorySalesFromSales(currentSales, currentItems);
    final staffSummaries =
        await _staffSummariesFromSales(currentSales, userId);
    final peakSalesPeriod = _peakSalesPeriodFromSales(currentSales, trend);

    return SalesAnalytics(
      bounds: bounds,
      totalSales: totalSales,
      transactionCount: transactionCount,
      averageTransaction: averageTransaction,
      itemsSold: itemsSold,
      comparison: comparison,
      trend: trend,
      previousTrend: previousTrend,
      paymentBreakdown: paymentBreakdown,
      topProducts: topProducts,
      categorySales: categorySales,
      staffSummaries: staffSummaries,
      peakSalesPeriod: peakSalesPeriod,
      sales: sales,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      staffUserId: userId,
    );
  }

  List<DailySalesPoint> _trendFromSales(
    List<Sale> sales,
    ReportingPeriodBounds bounds,
  ) {
    final grouped = <DateTime, DailySalesPoint>{};
    for (final sale in sales) {
      final key = _trendKey(sale.createdAt, bounds.groupBy);
      final existing = grouped[key];
      grouped[key] = DailySalesPoint(
        date: key,
        total: (existing?.total ?? 0.0) + sale.totalAmount,
        count: (existing?.count ?? 0) + 1,
      );
    }
    return _fillTrendGaps(grouped.values.toList(), bounds);
  }

  List<PaymentBreakdown> _paymentBreakdownFromSales(List<Sale> sales) {
    final grouped = <String, PaymentBreakdown>{};
    for (final sale in sales) {
      final method = sale.paymentMethod.isNotEmpty ? sale.paymentMethod : 'Unknown';
      final existing = grouped[method];
      grouped[method] = PaymentBreakdown(
        method: method,
        total: (existing?.total ?? 0.0) + sale.totalAmount,
        count: (existing?.count ?? 0) + 1,
      );
    }
    return grouped.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  List<TopProductResult> _topProductsFromItems(List<SaleItem> items) {
    final grouped = <int, TopProductResult>{};
    for (final item in items) {
      final name = item.productName?.isNotEmpty == true
          ? item.productName!
          : 'Product #${item.productId}';
      final existing = grouped[item.productId];
      grouped[item.productId] = TopProductResult(
        productId: item.productId,
        productName: name,
        totalQuantity: (existing?.totalQuantity ?? 0) + item.quantity,
        revenue: (existing?.revenue ?? 0.0) + item.totalPrice,
      );
    }
    final list = grouped.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list.take(10).toList();
  }

  Future<List<CategorySalesResult>> _categorySalesFromSales(
    List<Sale> sales,
    List<SaleItem> items,
  ) async {
    final products = await _productRepository.getAll();
    final productMap = {for (final p in products) p.id: p};
    final categories = await _categoryRepository.getAll();
    final categoryNames = {for (final c in categories) c.id: c.name};

    final saleTotalMap = {for (final s in sales) s.id: s.totalAmount};
    final categorySales = <int?, CategorySalesResult>{};
    final categorySaleIds = <int?, Set<int>>{};

    for (final item in items) {
      final product = productMap[item.productId];
      final categoryId = product?.categoryId;
      final categoryName = categoryNames[categoryId] ?? 'Uncategorized';
      final saleTotal = saleTotalMap[item.saleId] ?? 0.0;

      final existing = categorySales[categoryId];
      final ids = categorySaleIds.putIfAbsent(categoryId, () => <int>{});
      if (item.saleId != null) ids.add(item.saleId!);

      categorySales[categoryId] = CategorySalesResult(
        categoryId: categoryId,
        categoryName: categoryName,
        totalSales: (existing?.totalSales ?? 0.0) + saleTotal,
        transactionCount: ids.length,
        itemsSold: (existing?.itemsSold ?? 0) + item.quantity,
      );
    }

    return categorySales.values.toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
  }

  Future<List<StaffSalesSummary>> _staffSummariesFromSales(
    List<Sale> sales,
    int? filteredUserId,
  ) async {
    if (filteredUserId == null && !_canViewStaffPerformance) {
      return const [];
    }

    final users = await _userRepository.getAll();

    final byUser = <int, (double, int)>{};
    for (final sale in sales) {
      final existing = byUser[sale.userId];
      if (existing == null) {
        byUser[sale.userId] = (sale.totalAmount, 1);
      } else {
        byUser[sale.userId] = (
          existing.$1 + sale.totalAmount,
          existing.$2 + 1,
        );
      }
    }

    final summaries = <StaffSalesSummary>[];
    for (final user in users) {
      if (filteredUserId != null && user.id != filteredUserId) continue;
      if (filteredUserId == null && user.role != UserRole.staff) continue;

      final data = byUser[user.id];
      if (data == null) continue;

      summaries.add(StaffSalesSummary(
        userId: user.id!,
        fullName: user.fullName,
        role: user.role,
        totalSales: data.$1,
        transactionCount: data.$2,
      ));
    }

    return summaries..sort((a, b) => b.totalSales.compareTo(a.totalSales));
  }

  PeakSalesPeriod _peakSalesPeriodFromSales(
    List<Sale> sales,
    List<DailySalesPoint> trend,
  ) {
    final hourly = <int, SalesByHourPoint>{};
    for (final sale in sales) {
      final hour = sale.createdAt.hour;
      final existing = hourly[hour];
      hourly[hour] = SalesByHourPoint(
        hour: hour,
        total: (existing?.total ?? 0.0) + sale.totalAmount,
        count: (existing?.count ?? 0) + 1,
      );
    }

    SalesByHourPoint? peakHourPoint;
    for (final point in hourly.values) {
      if (peakHourPoint == null || point.total > peakHourPoint.total) {
        peakHourPoint = point;
      }
    }

    DailySalesPoint? peakDay;
    for (final point in trend) {
      if (peakDay == null || point.total > peakDay.total) {
        peakDay = point;
      }
    }

    return PeakSalesPeriod(
      peakHour: peakHourPoint?.hour,
      peakHourSales: peakHourPoint?.total ?? 0.0,
      peakHourTransactions: peakHourPoint?.count ?? 0,
      peakDay: peakDay?.date,
      peakDaySales: peakDay?.total ?? 0.0,
      peakDayTransactions: peakDay?.count ?? 0,
    );
  }

  List<DailySalesPoint> _fillTrendGaps(
    List<DailySalesPoint> points,
    ReportingPeriodBounds bounds,
  ) {
    // For week-level grouping the DAO returns daily rows, so collapse them
    // to week starts before filling.
    if (bounds.groupBy == ReportGroupBy.week) {
      points = _collapseToWeek(points);
    }

    final map = <DateTime, DailySalesPoint>{};
    for (final p in points) {
      map[_trendKey(p.date, bounds.groupBy)] = p;
    }

    final filled = <DailySalesPoint>[];
    var cursor = _trendKey(bounds.start, bounds.groupBy);
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

  /// Collapses daily sales points into week-start (Monday) buckets.
  List<DailySalesPoint> _collapseToWeek(List<DailySalesPoint> points) {
    final byWeek = <DateTime, DailySalesPoint>{};
    for (final p in points) {
      final week = startOfWeek(p.date);
      final existing = byWeek[week];
      if (existing == null) {
        byWeek[week] = p.copyWith(date: week);
      } else {
        byWeek[week] = existing.copyWith(
          total: existing.total + p.total,
          count: existing.count + p.count,
        );
      }
    }
    return byWeek.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  DateTime _trendKey(DateTime date, ReportGroupBy groupBy) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        return DateTime(date.year, date.month, date.day, date.hour);
      case ReportGroupBy.day:
        return DateTime(date.year, date.month, date.day);
      case ReportGroupBy.week:
        return startOfWeek(date);
      case ReportGroupBy.month:
        return DateTime(date.year, date.month, 1);
    }
  }

  DateTime _nextTrendStep(DateTime date, ReportGroupBy groupBy) {
    switch (groupBy) {
      case ReportGroupBy.hour:
        return date.add(const Duration(hours: 1));
      case ReportGroupBy.day:
        return date.add(const Duration(days: 1));
      case ReportGroupBy.week:
        return date.add(const Duration(days: 7));
      case ReportGroupBy.month:
        final next = DateTime(date.year, date.month + 1, 1);
        return next;
    }
  }

  /// Computes the busiest hour-of-day and the busiest calendar bucket for the
  /// selected [bounds].
  Future<PeakSalesPeriod> _computePeakSalesPeriod(
    List<DailySalesPoint> trend,
    ReportingPeriodBounds bounds, {
    int? userId,
  }) async {
    // Hour-of-day aggregation is meaningful for any range.
    final hourly = await _saleRepository.getSalesByHourOfDay(
      bounds.start,
      bounds.end,
      userId: userId,
    );

    SalesByHourPoint? peakHour;
    for (final h in hourly) {
      if (peakHour == null || h.total > peakHour.total) {
        peakHour = h;
      }
    }

    // Peak day/month is the largest point in the current period trend.
    DailySalesPoint? peakDay;
    for (final p in trend) {
      if (peakDay == null || p.total > peakDay.total) {
        peakDay = p;
      }
    }

    return PeakSalesPeriod(
      peakHour: peakHour?.hour,
      peakHourSales: peakHour?.total ?? 0.0,
      peakHourTransactions: peakHour?.count ?? 0,
      peakDay: peakDay?.date,
      peakDaySales: peakDay?.total ?? 0.0,
      peakDayTransactions: peakDay?.count ?? 0,
    );
  }

  /// Staff performance for the given period.
  Future<List<StaffSalesSummary>> getStaffPerformance(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_canViewReports || !_canViewStaffPerformance) return [];

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
