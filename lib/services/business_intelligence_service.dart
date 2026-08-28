import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/sale_item_dao.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/data/repositories/backup_history_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/export_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

/// Supported analytical intents the AI Business Advisor can handle.
///
/// Each intent maps to a set of controlled, predefined SQL queries executed
/// through the approved Repository → DAO → SQLite architecture. The AI
/// never writes or executes arbitrary SQL.
enum BusinessIntent {
  // ── Owner / business-wide intents ──
  todaySales,
  yesterdaySales,
  dateRangeSales,
  weeklySales,
  monthlySales,
  salesComparison,
  topProducts,
  lowSellingProducts,
  productPerformance,
  lowStock,
  restockRecommendation,
  categoryPerformance,
  busiestPeriod,
  inventoryStatus,
  businessSummary,
  trendAnalysis,
  // ── Admin / system-administrative intents ──
  activeUserSummary,
  userStatusSummary,
  systemActivitySummary,
  recentActivity,
  backupSummary,
  exportSummary,
  systemStatusSummary,
  adminSummary,
  // ── Staff / own-data intents (filtered by currentUserId) ──
  myTodaySales,
  myDateRangeSales,
  myRecentSales,
  myTopSoldProducts,
  productInformation,
  categoryInformation,
  myActivitySummary,
  myWorkSummary,
  // ── Shared ──
  general,
}

/// Detected intent and extracted parameters from a user query.
class DetectedIntent {
  final BusinessIntent intent;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? periodDescription;

  DetectedIntent({
    required this.intent,
    this.startDate,
    this.endDate,
    this.periodDescription,
  });
}

/// Structured business facts gathered from the database for a specific
/// intent. This is the ONLY data the AI receives — it never gets raw
/// database access.
class BusinessFacts {
  /// Human-readable summary of the facts (sent to Groq as context).
  final String context;

  /// The intent that was detected.
  final BusinessIntent intent;

  /// Whether any relevant data was found.
  final bool hasData;

  BusinessFacts({
    required this.context,
    required this.intent,
    required this.hasData,
  });
}

/// The Business Intelligence layer.
///
/// Architecture:
///   AI Advisor UI → Provider → AIAdvisorService → BusinessIntelligenceService
///     → Repository → DAO → SQLite → Aggregated Facts → AIAdvisorService
///     → Context Builder → Groq → Business Explanation
///
/// This service:
/// - Detects the user's analytical intent from natural language
/// - Executes ONLY predefined, safe SQL queries through repositories
/// - Aggregates the results into structured business facts
/// - Returns a context string containing ONLY the relevant data
///
/// The AI NEVER gets arbitrary SQL execution access. The AI NEVER sees
/// the raw database file. The AI only sees the aggregated facts returned
/// by this service.
///
/// Security:
/// - Never includes password_hash, pin, API keys, or sensitive config
/// - Excludes soft-deleted and inactive records
/// - Excludes voided sales from normal analytics
/// - Only queries approved business domains
class BusinessIntelligenceService {
  final SaleRepository _saleRepository = SaleRepository();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final SaleItemDao _saleItemDao = SaleItemDao();
  // Admin-domain repositories (used only for Admin AI intents).
  final UserRepository _userRepository = UserRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final BackupHistoryRepository _backupHistoryRepository =
      BackupHistoryRepository();
  final ExportHistoryRepository _exportHistoryRepository =
      ExportHistoryRepository();
  final SettingsRepository _settingsRepository = SettingsRepository();
  final SessionManager _sessionManager = SessionManager();

  /// Detects the analytical intent from a user's natural-language query.
  ///
  /// When [role] is provided, role-specific intent patterns are checked
  /// first so the same question maps to the correct role-scoped intent
  /// (e.g. "how much did I sell today?" → [BusinessIntent.myTodaySales]
  /// for Staff but [BusinessIntent.todaySales] for Owner).
  ///
  /// Uses keyword matching against known intent patterns. Returns
  /// [BusinessIntent.general] if no specific intent is detected (the AI
  /// can still answer generally but must not invent database facts).
  DetectedIntent detectIntent(String query, {UserRole? role}) {
    final q = query.toLowerCase();

    // ── Date range detection (shared by all roles) ──
    DateTime? startDate;
    DateTime? endDate;
    String? periodDesc;

    final now = DateTime.now();
    final today = startOfDay(now);

    if (q.contains('today') || q.contains('right now') || q.contains('day')) {
      startDate = today;
      endDate = today.add(const Duration(days: 1));
      periodDesc = 'today';
    } else if (q.contains('yesterday')) {
      startDate = today.subtract(const Duration(days: 1));
      endDate = today;
      periodDesc = 'yesterday';
    } else if (q.contains('this week') || q.contains('week')) {
      final weekday = now.weekday;
      startDate = today.subtract(Duration(days: weekday - 1));
      endDate = startDate.add(const Duration(days: 7));
      periodDesc = 'this week';
    } else if (q.contains('last week')) {
      final weekday = now.weekday;
      final thisWeekStart = today.subtract(Duration(days: weekday - 1));
      startDate = thisWeekStart.subtract(const Duration(days: 7));
      endDate = thisWeekStart;
      periodDesc = 'last week';
    } else if (q.contains('this month') || q.contains('month')) {
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 1);
      periodDesc = 'this month';
    } else if (q.contains('last month')) {
      startDate = DateTime(now.year, now.month - 1, 1);
      endDate = DateTime(now.year, now.month, 1);
      periodDesc = 'last month';
    }

    // ── Role-specific intent detection ──
    //
    // Admin and Staff get their own intent sets first, so a question like
    // "how much did we make today?" maps to myTodaySales for Staff (own
    // sales only) rather than todaySales (business-wide).
    if (role == UserRole.admin) {
      return _detectAdminIntent(q, startDate, endDate, periodDesc);
    }
    if (role == UserRole.staff) {
      return _detectStaffIntent(q, startDate, endDate, periodDesc);
    }

    // ── Owner / business-wide intent detection ──

    // Sales queries
    if (_matches(q, ['how were my sales', 'how are my sales', 'sales today',
        'sales performance', 'how did i do', 'how am i doing',
        'total sales', 'sales this', 'my sales']) ||
        (q.contains('sales') && (q.contains('today') || q.contains('week') ||
            q.contains('month') || q.contains('yesterday')))) {
      if (q.contains('compare') || q.contains('vs') || q.contains('versus') ||
          q.contains('difference') || q.contains('change') ||
          q.contains('decrease') || q.contains('increase') ||
          q.contains('decline') || q.contains('drop')) {
        return DetectedIntent(
          intent: BusinessIntent.salesComparison,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      if (periodDesc == 'today' || (q.contains('today') && q.contains('sales'))) {
        return DetectedIntent(
          intent: BusinessIntent.todaySales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      if (periodDesc == 'yesterday') {
        return DetectedIntent(
          intent: BusinessIntent.yesterdaySales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      if (periodDesc != null && periodDesc.contains('week')) {
        return DetectedIntent(
          intent: BusinessIntent.weeklySales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      if (periodDesc != null && periodDesc.contains('month')) {
        return DetectedIntent(
          intent: BusinessIntent.monthlySales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      return DetectedIntent(
        intent: BusinessIntent.dateRangeSales,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Top / best-selling products
    if (_matches(q, ['best selling', 'best-selling', 'top product',
        'top selling', 'most sold', 'selling the most',
        'what products are selling', 'popular product'])) {
      return DetectedIntent(
        intent: BusinessIntent.topProducts,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Low-selling / poorly performing products
    if (_matches(q, ['low selling', 'poorly', 'worst selling',
        'not selling', 'slow moving', 'least sold', 'underperforming'])) {
      return DetectedIntent(
        intent: BusinessIntent.lowSellingProducts,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Product performance
    if (_matches(q, ['product performance', 'how are my products',
        'which products are performing'])) {
      return DetectedIntent(
        intent: BusinessIntent.productPerformance,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Low stock / restock
    if (_matches(q, ['low stock', 'low on stock', 'running low',
        'out of stock', 'stock level', 'below minimum'])) {
      return DetectedIntent(
        intent: BusinessIntent.lowStock,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    if (_matches(q, ['restock', 'reorder', 'what should i restock',
        'what to order', 'need to buy', 'replenish'])) {
      return DetectedIntent(
        intent: BusinessIntent.restockRecommendation,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Category performance
    if (_matches(q, ['category performance', 'best category',
        'which categories', 'category sales', 'top category'])) {
      return DetectedIntent(
        intent: BusinessIntent.categoryPerformance,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Inventory status
    if (_matches(q, ['inventory status', 'inventory report',
        'stock status', 'stock report', 'my inventory'])) {
      return DetectedIntent(
        intent: BusinessIntent.inventoryStatus,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Busiest period
    if (_matches(q, ['busiest day', 'busiest time', 'peak sales',
        'best day', 'which day', 'busy period'])) {
      return DetectedIntent(
        intent: BusinessIntent.busiestPeriod,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Trend analysis
    if (_matches(q, ['trend', 'pattern', 'unusual', 'why did sales',
        'why might sales', 'what happened to sales',
        'sales decreased', 'sales dropped', 'sales went down'])) {
      return DetectedIntent(
        intent: BusinessIntent.trendAnalysis,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Business summary / overview
    if (_matches(q, ['business summary', 'overview', 'give me a summary',
        'business performance', 'how is my business',
        'business report', 'summary of', 'what should i focus',
        'recommendations for', 'recommend for my business',
        'what should i do', 'focus on tomorrow', 'advice for'])) {
      return DetectedIntent(
        intent: BusinessIntent.businessSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    return DetectedIntent(
      intent: BusinessIntent.general,
      startDate: startDate,
      endDate: endDate,
      periodDescription: periodDesc,
    );
  }

  /// Gathers relevant business facts for the detected intent.
  ///
  /// Only fetches data from the approved business domains needed for the
  /// specific intent. Does NOT fetch unrelated data. Does NOT expose
  /// sensitive fields.
  ///
  /// [role] and [userId] are used for Staff queries which are filtered by
  /// the authenticated user ID at the database query layer
  /// (`sales.user_id = currentUserId`).
  Future<BusinessFacts> gatherFacts(
    DetectedIntent detected, {
    UserRole? role,
    int? userId,
  }) async {
    try {
      switch (detected.intent) {
        // ── Owner / business-wide ──
        case BusinessIntent.todaySales:
          return await _gatherTodaySales(detected);
        case BusinessIntent.yesterdaySales:
          return await _gatherYesterdaySales(detected);
        case BusinessIntent.dateRangeSales:
          return await _gatherDateRangeSales(detected);
        case BusinessIntent.weeklySales:
          return await _gatherWeeklySales(detected);
        case BusinessIntent.monthlySales:
          return await _gatherMonthlySales(detected);
        case BusinessIntent.salesComparison:
          return await _gatherSalesComparison(detected);
        case BusinessIntent.topProducts:
          return await _gatherTopProducts(detected);
        case BusinessIntent.lowSellingProducts:
          return await _gatherLowSellingProducts(detected);
        case BusinessIntent.productPerformance:
          return await _gatherProductPerformance(detected);
        case BusinessIntent.lowStock:
          return await _gatherLowStock(detected);
        case BusinessIntent.restockRecommendation:
          return await _gatherRestockRecommendation(detected);
        case BusinessIntent.categoryPerformance:
          return await _gatherCategoryPerformance(detected);
        case BusinessIntent.busiestPeriod:
          return await _gatherBusiestPeriod(detected);
        case BusinessIntent.inventoryStatus:
          return await _gatherInventoryStatus(detected);
        case BusinessIntent.businessSummary:
          return await _gatherBusinessSummary(detected);
        case BusinessIntent.trendAnalysis:
          return await _gatherTrendAnalysis(detected);
        // ── Admin / system-administrative ──
        case BusinessIntent.activeUserSummary:
          return await _gatherActiveUserSummary(detected);
        case BusinessIntent.userStatusSummary:
          return await _gatherUserStatusSummary(detected);
        case BusinessIntent.systemActivitySummary:
          return await _gatherSystemActivitySummary(detected);
        case BusinessIntent.recentActivity:
          return await _gatherRecentActivity(detected);
        case BusinessIntent.backupSummary:
          return await _gatherBackupSummary(detected);
        case BusinessIntent.exportSummary:
          return await _gatherExportSummary(detected);
        case BusinessIntent.systemStatusSummary:
          return await _gatherSystemStatusSummary(detected);
        case BusinessIntent.adminSummary:
          return await _gatherAdminSummary(detected);
        // ── Staff / own-data (filtered by currentUserId) ──
        case BusinessIntent.myTodaySales:
          return await _gatherMyTodaySales(detected, userId);
        case BusinessIntent.myDateRangeSales:
          return await _gatherMyDateRangeSales(detected, userId);
        case BusinessIntent.myRecentSales:
          return await _gatherMyRecentSales(detected, userId);
        case BusinessIntent.myTopSoldProducts:
          return await _gatherMyTopSoldProducts(detected, userId);
        case BusinessIntent.productInformation:
          return await _gatherProductInformation(detected);
        case BusinessIntent.categoryInformation:
          return await _gatherCategoryInformation(detected);
        case BusinessIntent.myActivitySummary:
          return await _gatherMyActivitySummary(detected, userId);
        case BusinessIntent.myWorkSummary:
          return await _gatherMyWorkSummary(detected, userId);
        // ── Shared ──
        case BusinessIntent.general:
          return await _gatherGeneralContext(detected, role: role);
      }
    } catch (e, st) {
      _log('gatherFacts failed for intent ${detected.intent}: $e\n$st');
      return BusinessFacts(
        context: 'Unable to retrieve business data at this time. '
            'Please try again.',
        intent: detected.intent,
        hasData: false,
      );
    }
  }

  // ── Intent-specific data gathering ───────────────────────────────────
  //
  // Each method executes ONLY predefined safe queries through the approved
  // Repository → DAO → SQLite architecture. The AI never sees raw SQL,
  // never executes arbitrary queries, and never gets the database file.

  Future<BusinessFacts> _gatherTodaySales(DetectedIntent d) async {
    final now = DateTime.now();
    final today = startOfDay(now);
    final sales = await _saleRepository.getByDateRange(
      today,
      today.add(const Duration(days: 1)),
    );
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final total = activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count = activeSales.length;
    final avg = count > 0 ? total / count : 0.0;

    // Also fetch yesterday for comparison context.
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdaySales = await _saleRepository.getByDateRange(
      yesterday,
      today,
    );
    final yesterdayActive =
        yesterdaySales.where((s) => !s.isDeleted).toList();
    final yesterdayTotal =
        yesterdayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final yesterdayCount = yesterdayActive.length;

    final change = yesterdayTotal > 0
        ? ((total - yesterdayTotal) / yesterdayTotal) * 100
        : null;

    final buf = StringBuffer();
    buf.writeln('--- TODAY\'S SALES DATA ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('Total sales today: PHP ${_formatMoney(total)}');
    buf.writeln('Number of transactions today: $count');
    buf.writeln('Average transaction value today: PHP ${_formatMoney(avg)}');
    buf.writeln('');
    buf.writeln('Yesterday (${_formatDate(yesterday)}):');
    buf.writeln('  Total: PHP ${_formatMoney(yesterdayTotal)}');
    buf.writeln('  Transactions: $yesterdayCount');
    if (change != null) {
      buf.writeln(
          '  Change from yesterday: ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%');
    }
    if (count == 0) {
      buf.writeln('');
      buf.writeln('NOTE: No sales have been recorded today yet.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherYesterdaySales(DetectedIntent d) async {
    final now = DateTime.now();
    final today = startOfDay(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final sales = await _saleRepository.getByDateRange(yesterday, today);
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final total = activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count = activeSales.length;
    final avg = count > 0 ? total / count : 0.0;

    final buf = StringBuffer();
    buf.writeln('--- YESTERDAY\'S SALES DATA ---');
    buf.writeln('Date: ${_formatDate(yesterday)}');
    buf.writeln('Total sales: PHP ${_formatMoney(total)}');
    buf.writeln('Number of transactions: $count');
    buf.writeln('Average transaction value: PHP ${_formatMoney(avg)}');
    if (count == 0) {
      buf.writeln('NOTE: No sales were recorded on this day.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherDateRangeSales(DetectedIntent d) async {
    final start = d.startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = d.endDate ?? DateTime.now().add(const Duration(days: 1));
    final sales = await _saleRepository.getByDateRange(start, end);
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final total = activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count = activeSales.length;
    final avg = count > 0 ? total / count : 0.0;

    final buf = StringBuffer();
    buf.writeln('--- SALES DATA (${d.periodDescription ?? 'custom range'}) ---');
    buf.writeln('Period: ${_formatDate(start)} to ${_formatDate(end)}');
    buf.writeln('Total sales: PHP ${_formatMoney(total)}');
    buf.writeln('Number of transactions: $count');
    buf.writeln('Average transaction value: PHP ${_formatMoney(avg)}');
    if (count > 0) {
      buf.writeln('First sale: ${_formatDateTime(activeSales.last.createdAt)}');
      buf.writeln('Last sale: ${_formatDateTime(activeSales.first.createdAt)}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: count > 0,
    );
  }

  Future<BusinessFacts> _gatherWeeklySales(DetectedIntent d) async {
    final start = d.startDate ?? _startOfWeek();
    final end = d.endDate ?? start.add(const Duration(days: 7));
    return _gatherDateRangeSales(DetectedIntent(
      intent: d.intent,
      startDate: start,
      endDate: end,
      periodDescription: d.periodDescription ?? 'this week',
    ));
  }

  Future<BusinessFacts> _gatherMonthlySales(DetectedIntent d) async {
    final now = DateTime.now();
    final start = d.startDate ?? DateTime(now.year, now.month, 1);
    final end = d.endDate ?? DateTime(now.year, now.month + 1, 1);
    return _gatherDateRangeSales(DetectedIntent(
      intent: d.intent,
      startDate: start,
      endDate: end,
      periodDescription: d.periodDescription ?? 'this month',
    ));
  }

  Future<BusinessFacts> _gatherSalesComparison(DetectedIntent d) async {
    final now = DateTime.now();
    final today = startOfDay(now);

    // Determine the two periods to compare.
    DateTime period1Start, period1End, period2Start, period2End;
    String period1Label, period2Label;

    if (d.periodDescription == 'this week' || d.periodDescription == 'last week') {
      final weekday = now.weekday;
      final thisWeekStart = today.subtract(Duration(days: weekday - 1));
      if (d.periodDescription == 'last week') {
        period2Start = thisWeekStart.subtract(const Duration(days: 7));
        period2End = thisWeekStart;
        period1Start = thisWeekStart.subtract(const Duration(days: 14));
        period1End = thisWeekStart.subtract(const Duration(days: 7));
        period2Label = 'last week';
        period1Label = 'the week before';
      } else {
        period2Start = thisWeekStart;
        period2End = thisWeekStart.add(const Duration(days: 7));
        period1Start = thisWeekStart.subtract(const Duration(days: 7));
        period1End = thisWeekStart;
        period2Label = 'this week';
        period1Label = 'last week';
      }
    } else if (d.periodDescription != null && d.periodDescription!.contains('month')) {
      if (d.periodDescription == 'last month') {
        period2Start = DateTime(now.year, now.month - 1, 1);
        period2End = DateTime(now.year, now.month, 1);
        period1Start = DateTime(now.year, now.month - 2, 1);
        period1End = DateTime(now.year, now.month - 1, 1);
        period2Label = 'last month';
        period1Label = 'the month before';
      } else {
        period2Start = DateTime(now.year, now.month, 1);
        period2End = DateTime(now.year, now.month + 1, 1);
        period1Start = DateTime(now.year, now.month - 1, 1);
        period1End = DateTime(now.year, now.month, 1);
        period2Label = 'this month';
        period1Label = 'last month';
      }
    } else {
      // Default: today vs yesterday
      period2Start = today;
      period2End = today.add(const Duration(days: 1));
      period1Start = today.subtract(const Duration(days: 1));
      period1End = today;
      period2Label = 'today';
      period1Label = 'yesterday';
    }

    final sales1 = await _saleRepository.getByDateRange(period1Start, period1End);
    final sales2 = await _saleRepository.getByDateRange(period2Start, period2End);
    final active1 = sales1.where((s) => !s.isDeleted).toList();
    final active2 = sales2.where((s) => !s.isDeleted).toList();

    final total1 = active1.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final total2 = active2.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count1 = active1.length;
    final count2 = active2.length;
    final change = total1 > 0
        ? ((total2 - total1) / total1) * 100
        : null;

    final buf = StringBuffer();
    buf.writeln('--- SALES COMPARISON DATA ---');
    buf.writeln('$period1Label (${_formatDate(period1Start)} – ${_formatDate(period1End.subtract(const Duration(days: 1)))}):');
    buf.writeln('  Total: PHP ${_formatMoney(total1)}');
    buf.writeln('  Transactions: $count1');
    buf.writeln('$period2Label (${_formatDate(period2Start)} – ${_formatDate(period2End.subtract(const Duration(days: 1)))}):');
    buf.writeln('  Total: PHP ${_formatMoney(total2)}');
    buf.writeln('  Transactions: $count2');
    if (change != null) {
      buf.writeln(
          'Change: ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%');
      buf.writeln(
          'Difference: PHP ${_formatMoney((total2 - total1).abs())} ${change >= 0 ? 'increase' : 'decrease'}');
    } else if (total1 == 0 && total2 > 0) {
      buf.writeln('No sales in $period1Label to compare against.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherTopProducts(DetectedIntent d) async {
    final since = d.startDate;
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 10,
      since: since,
    );

    final buf = StringBuffer();
    buf.writeln('--- TOP-SELLING PRODUCTS (${d.periodDescription ?? 'all time'}) ---');
    if (topProducts.isEmpty) {
      buf.writeln('No sales data available for this period.');
    } else {
      for (var i = 0; i < topProducts.length; i++) {
        final p = topProducts[i];
        buf.writeln(
            '${i + 1}. ${p['product_name']} — ${p['total_quantity']} units sold');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: topProducts.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherLowSellingProducts(DetectedIntent d) async {
    // Get all active products, then cross-reference with sales data.
    final products = await _productRepository.getActiveProducts();
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 100,
      since: d.startDate,
    );

    // Build a map of product_id → quantity sold.
    final soldMap = <int, int>{};
    for (final p in topProducts) {
      final pid = p['product_id'] as int;
      final qty = p['total_quantity'] as int;
      soldMap[pid] = qty;
    }

    // Products with zero or very low sales.
    final lowSellers = products.where((p) {
      final sold = soldMap[p.id] ?? 0;
      return sold <= 2;
    }).toList();

    final buf = StringBuffer();
    buf.writeln('--- LOW-SELLING PRODUCTS (${d.periodDescription ?? 'all time'}) ---');
    if (lowSellers.isEmpty) {
      buf.writeln('All active products have meaningful sales.');
    } else {
      buf.writeln('Products with 0-2 units sold:');
      for (final p in lowSellers.take(15)) {
        final sold = soldMap[p.id] ?? 0;
        buf.writeln('  - ${p.name}: $sold units sold (stock: ${p.stock})');
      }
    }
    buf.writeln('Total active products: ${products.length}');
    buf.writeln('Products with low sales: ${lowSellers.length}');
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: products.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherProductPerformance(DetectedIntent d) async {
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 20,
      since: d.startDate,
    );
    final allProducts = await _productRepository.getActiveProducts();

    final buf = StringBuffer();
    buf.writeln('--- PRODUCT PERFORMANCE (${d.periodDescription ?? 'all time'}) ---');
    buf.writeln('Total active products: ${allProducts.length}');
    if (topProducts.isEmpty) {
      buf.writeln('No sales data available.');
    } else {
      buf.writeln('Products ranked by units sold:');
      for (var i = 0; i < topProducts.length; i++) {
        final p = topProducts[i];
        buf.writeln(
            '  ${i + 1}. ${p['product_name']} — ${p['total_quantity']} units');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: topProducts.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherLowStock(DetectedIntent d) async {
    final lowStockProducts = await _productRepository.getLowStockProducts();

    final buf = StringBuffer();
    buf.writeln('--- LOW STOCK DATA ---');
    if (lowStockProducts.isEmpty) {
      buf.writeln('No products are below their minimum stock level.');
    } else {
      buf.writeln('Products at or below minimum stock level:');
      for (final p in lowStockProducts) {
        buf.writeln(
            '  - ${p.name}: ${p.stock} units remaining (minimum: ${p.minStock})');
      }
    }
    buf.writeln('Total low-stock items: ${lowStockProducts.length}');
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherRestockRecommendation(DetectedIntent d) async {
    final lowStockProducts = await _productRepository.getLowStockProducts();
    final allProducts = await _productRepository.getActiveProducts();

    // Get recent sales velocity for low-stock products.
    final recentSales = await _saleItemDao.getTopProductsByQuantity(
      limit: 50,
      since: DateTime.now().subtract(const Duration(days: 7)),
    );
    final velocityMap = <int, int>{};
    for (final p in recentSales) {
      velocityMap[p['product_id'] as int] = p['total_quantity'] as int;
    }

    final buf = StringBuffer();
    buf.writeln('--- RESTOCK RECOMMENDATION DATA ---');
    if (lowStockProducts.isEmpty) {
      buf.writeln('All products are above their minimum stock level. No urgent restocking needed.');
    } else {
      buf.writeln('Products needing restock (sorted by urgency):');
      // Sort by how far below minimum they are.
      final sorted = lowStockProducts
        ..sort((a, b) => (a.stock - a.minStock).compareTo(b.stock - b.minStock));
      for (final p in sorted) {
        final velocity = velocityMap[p.id] ?? 0;
        final deficit = p.minStock - p.stock;
        buf.writeln(
            '  - ${p.name}: ${p.stock} units (min: ${p.minStock}, deficit: $deficit, last 7 days sold: $velocity units)');
      }
    }
    buf.writeln('Total active products: ${allProducts.length}');
    buf.writeln('Products needing restock: ${lowStockProducts.length}');
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherCategoryPerformance(DetectedIntent d) async {
    final categories = await _categoryRepository.getActiveCategories();
    final products = await _productRepository.getActiveProducts();
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 100,
      since: d.startDate,
    );

    // Build category → product count and category → units sold.
    final catProductCount = <int, int>{};
    for (final p in products) {
      if (p.categoryId != null) {
        catProductCount[p.categoryId!] =
            (catProductCount[p.categoryId!] ?? 0) + 1;
      }
    }

    // Map product_id → category_id.
    final productToCategory = <int, int?>{};
    for (final p in products) {
      productToCategory[p.id!] = p.categoryId;
    }

    final catUnitsSold = <int, int>{};
    for (final tp in topProducts) {
      final pid = tp['product_id'] as int;
      final qty = tp['total_quantity'] as int;
      final catId = productToCategory[pid];
      if (catId != null) {
        catUnitsSold[catId] = (catUnitsSold[catId] ?? 0) + qty;
      }
    }

    final buf = StringBuffer();
    buf.writeln('--- CATEGORY PERFORMANCE (${d.periodDescription ?? 'all time'}) ---');
    buf.writeln('Total active categories: ${categories.length}');
    for (final cat in categories) {
      final productCount = catProductCount[cat.id] ?? 0;
      final unitsSold = catUnitsSold[cat.id] ?? 0;
      buf.writeln('  - ${cat.name}: $productCount products, $unitsSold units sold');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: categories.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherBusiestPeriod(DetectedIntent d) async {
    // Get last 30 days of sales and group by day of week.
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final sales = await _saleRepository.getByDateRange(
      start,
      now.add(const Duration(days: 1)),
    );
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    // Group by day of week (1=Monday ... 7=Sunday).
    final dayTotals = <int, double>{};
    final dayCounts = <int, int>{};
    for (final s in activeSales) {
      final weekday = s.createdAt.weekday;
      dayTotals[weekday] = (dayTotals[weekday] ?? 0) + s.totalAmount;
      dayCounts[weekday] = (dayCounts[weekday] ?? 0) + 1;
    }

    const dayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'];

    final buf = StringBuffer();
    buf.writeln('--- BUSIEST PERIOD DATA (last 30 days) ---');
    buf.writeln('Total transactions in last 30 days: ${activeSales.length}');
    if (activeSales.isEmpty) {
      buf.writeln('No sales data available for the last 30 days.');
    } else {
      buf.writeln('Sales by day of week:');
      for (var i = 1; i <= 7; i++) {
        final total = dayTotals[i] ?? 0;
        final count = dayCounts[i] ?? 0;
        buf.writeln('  - ${dayNames[i]}: PHP ${_formatMoney(total)} ($count transactions)');
      }
      // Find the busiest day.
      var busiestDay = 1;
      var maxTotal = 0.0;
      dayTotals.forEach((day, total) {
        if (total > maxTotal) {
          maxTotal = total;
          busiestDay = day;
        }
      });
      buf.writeln('Busiest day: ${dayNames[busiestDay]}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: activeSales.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherInventoryStatus(DetectedIntent d) async {
    final products = await _productRepository.getActiveProducts();
    final lowStock = await _productRepository.getLowStockProducts();
    final outOfStock = products.where((p) => p.stock == 0).toList();

    final totalValue = products.fold<double>(
      0, (sum, p) => sum + (p.price * p.stock));

    final buf = StringBuffer();
    buf.writeln('--- INVENTORY STATUS ---');
    buf.writeln('Total active products: ${products.length}');
    buf.writeln('Products at/below minimum stock: ${lowStock.length}');
    buf.writeln('Products out of stock (0 units): ${outOfStock.length}');
    buf.writeln('Estimated inventory value: PHP ${_formatMoney(totalValue)}');
    if (lowStock.isNotEmpty) {
      buf.writeln('Low stock items:');
      for (final p in lowStock.take(10)) {
        buf.writeln(
            '  - ${p.name}: ${p.stock} units (min: ${p.minStock})');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherBusinessSummary(DetectedIntent d) async {
    final now = DateTime.now();
    final today = startOfDay(now);

    // Today's sales.
    final todaySales = await _saleRepository.getByDateRange(
      today, today.add(const Duration(days: 1)));
    final todayActive = todaySales.where((s) => !s.isDeleted).toList();
    final todayTotal =
        todayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);

    // This month's sales.
    final monthStart = DateTime(now.year, now.month, 1);
    final monthSales = await _saleRepository.getByDateRange(
      monthStart, DateTime(now.year, now.month + 1, 1));
    final monthActive = monthSales.where((s) => !s.isDeleted).toList();
    final monthTotal =
        monthActive.fold<double>(0, (sum, s) => sum + s.totalAmount);

    // Yesterday for comparison.
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdaySales = await _saleRepository.getByDateRange(yesterday, today);
    final yesterdayActive =
        yesterdaySales.where((s) => !s.isDeleted).toList();
    final yesterdayTotal =
        yesterdayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);

    // Top products (last 7 days).
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 5,
      since: now.subtract(const Duration(days: 7)),
    );

    // Low stock.
    final lowStock = await _productRepository.getLowStockProducts();

    // Products count.
    final allProducts = await _productRepository.getActiveProducts();

    final todayChange = yesterdayTotal > 0
        ? ((todayTotal - yesterdayTotal) / yesterdayTotal) * 100
        : null;

    final buf = StringBuffer();
    buf.writeln('--- BUSINESS SUMMARY ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('');
    buf.writeln('SALES:');
    buf.writeln('  Today: PHP ${_formatMoney(todayTotal)} (${todayActive.length} transactions)');
    if (todayChange != null) {
      buf.writeln(
          '  vs Yesterday: PHP ${_formatMoney(yesterdayTotal)} (${todayChange >= 0 ? '+' : ''}${todayChange.toStringAsFixed(1)}%)');
    }
    buf.writeln('  This month: PHP ${_formatMoney(monthTotal)} (${monthActive.length} transactions)');
    buf.writeln('');
    buf.writeln('TOP PRODUCTS (last 7 days):');
    if (topProducts.isEmpty) {
      buf.writeln('  No sales in the last 7 days.');
    } else {
      for (var i = 0; i < topProducts.length; i++) {
        final p = topProducts[i];
        buf.writeln('  ${i + 1}. ${p['product_name']} — ${p['total_quantity']} units');
      }
    }
    buf.writeln('');
    buf.writeln('INVENTORY:');
    buf.writeln('  Active products: ${allProducts.length}');
    buf.writeln('  Low stock items: ${lowStock.length}');
    if (lowStock.isNotEmpty) {
      for (final p in lowStock.take(5)) {
        buf.writeln('    - ${p.name}: ${p.stock} units (min: ${p.minStock})');
      }
    }
    buf.writeln('--- END SUMMARY ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherTrendAnalysis(DetectedIntent d) async {
    // Get last 14 days of sales for trend analysis.
    final now = DateTime.now();
    final today = startOfDay(now);
    final twoWeeksAgo = today.subtract(const Duration(days: 14));

    final sales = await _saleRepository.getByDateRange(
      twoWeeksAgo, today.add(const Duration(days: 1)));
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    // Group by day.
    final dailyTotals = <DateTime, double>{};
    final dailyCounts = <DateTime, int>{};
    for (final s in activeSales) {
      final day = DateTime(
          s.createdAt.year, s.createdAt.month, s.createdAt.day);
      dailyTotals[day] = (dailyTotals[day] ?? 0) + s.totalAmount;
      dailyCounts[day] = (dailyCounts[day] ?? 0) + 1;
    }

    // Calculate week-over-week.
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

    final thisWeekTotal = dailyTotals.entries
        .where((e) => e.key.isAfter(lastWeekStart.add(const Duration(days: 7))))
        .fold<double>(0, (sum, e) => sum + e.value);
    final lastWeekTotal = dailyTotals.entries
        .where((e) =>
            e.key.isAfter(lastWeekStart.subtract(const Duration(days: 1))) &&
            e.key.isBefore(thisWeekStart))
        .fold<double>(0, (sum, e) => sum + e.value);

    final weekChange = lastWeekTotal > 0
        ? ((thisWeekTotal - lastWeekTotal) / lastWeekTotal) * 100
        : null;

    final buf = StringBuffer();
    buf.writeln('--- SALES TREND DATA (last 14 days) ---');
    buf.writeln('Total transactions in last 14 days: ${activeSales.length}');
    buf.writeln('');
    buf.writeln('Daily sales:');
    for (var i = 0; i < 14; i++) {
      final day = twoWeeksAgo.add(Duration(days: i));
      final total = dailyTotals[day] ?? 0;
      final count = dailyCounts[day] ?? 0;
      buf.writeln('  ${_formatDate(day)}: PHP ${_formatMoney(total)} ($count transactions)');
    }
    buf.writeln('');
    buf.writeln('Week comparison:');
    buf.writeln('  This week (so far): PHP ${_formatMoney(thisWeekTotal)}');
    buf.writeln('  Last week: PHP ${_formatMoney(lastWeekTotal)}');
    if (weekChange != null) {
      buf.writeln(
          '  Change: ${weekChange >= 0 ? '+' : ''}${weekChange.toStringAsFixed(1)}%');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: activeSales.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherGeneralContext(
    DetectedIntent d, {
    UserRole? role,
  }) async {
    final buf = StringBuffer();

    // Add store and user context to every AI context so the assistant can
    // personalize its answer and avoid claiming missing business identity.
    final store = await _settingsRepository.getSettings();
    if (store != null) {
      buf.writeln('--- STORE CONTEXT ---');
      buf.writeln('Store: ${store.storeName}');
      if (store.storeAddress.isNotEmpty) {
        buf.writeln('Address: ${store.storeAddress}');
      }
      if (store.storePhone.isNotEmpty) {
        buf.writeln('Contact: ${store.storePhone}');
      }
      buf.writeln('Currency: ${store.currency}');
      buf.writeln('--- END STORE CONTEXT ---');
      buf.writeln('');
    }

    final currentUser = _sessionManager.currentUser;
    if (currentUser != null) {
      buf.writeln('--- USER CONTEXT ---');
      buf.writeln('User: ${currentUser.fullName}');
      buf.writeln('Role: ${currentUser.role.displayName}');
      buf.writeln('--- END USER CONTEXT ---');
      buf.writeln('');
    }

    if (role == UserRole.admin) {
      // Admin general context: system overview only.
      final users = await _userRepository.getAllActive();
      final activeUsers = users.where((u) => u.isActive).length;
      final inactiveUsers = users.length - activeUsers;
      final recentActivity =
          await _activityLogRepository.getRecentActivities(limit: 5);
      final backups = await _backupHistoryRepository.getAllActive();

      buf.writeln('--- GENERAL SYSTEM CONTEXT ---');
      buf.writeln('Total active users: ${users.length}');
      buf.writeln('Active: $activeUsers, Inactive: $inactiveUsers');
      buf.writeln('Recent activities: ${recentActivity.length}');
      buf.writeln('Total backups: ${backups.length}');
      buf.writeln('');
      buf.writeln('NOTE: This is general system context only. For specific '
          'analysis, ask about users, system activity, backups, or request '
          'a system summary.');
      buf.writeln('--- END CONTEXT ---');
    } else if (role == UserRole.staff) {
      // Staff general context: own data only, filtered by currentUserId.
      final userId = _sessionManager.currentUser?.id;
      if (userId == null) {
        buf.writeln('--- GENERAL WORK CONTEXT ---');
        buf.writeln('Unable to identify current user. Please try again.');
        buf.writeln('--- END CONTEXT ---');
      } else {
        final now = DateTime.now();
        final today = startOfDay(now);
        final mySales = await _saleRepository.getByDateRangeAndUser(
          today, today.add(const Duration(days: 1)), userId);
        final myActive = mySales.where((s) => !s.isDeleted).toList();
        final myTotal =
            myActive.fold<double>(0, (sum, s) => sum + s.totalAmount);
        final products = await _productRepository.getActiveProducts();
        final lowStock = await _productRepository.getLowStockProducts();

        buf.writeln('--- GENERAL WORK CONTEXT (your data) ---');
        buf.writeln('Your sales today: PHP ${_formatMoney(myTotal)} '
            '(${myActive.length} transactions)');
        buf.writeln('Active products: ${products.length}');
        buf.writeln('Low stock items: ${lowStock.length}');
        buf.writeln('');
        buf.writeln('NOTE: This is your own work context. For specific '
            'analysis, ask about your sales, low stock, or products.');
        buf.writeln('--- END CONTEXT ---');
      }
    } else {
      // Owner general context: business overview.
      final now = DateTime.now();
      final today = startOfDay(now);
      final todaySales = await _saleRepository.getByDateRange(
        today, today.add(const Duration(days: 1)));
      final todayActive = todaySales.where((s) => !s.isDeleted).toList();
      final todayTotal =
          todayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);
      final products = await _productRepository.getActiveProducts();
      final lowStock = await _productRepository.getLowStockProducts();

      buf.writeln('--- GENERAL BUSINESS CONTEXT ---');
      buf.writeln('Today\'s sales: PHP ${_formatMoney(todayTotal)} '
          '(${todayActive.length} transactions)');
      buf.writeln('Active products: ${products.length}');
      buf.writeln('Low stock items: ${lowStock.length}');
      buf.writeln('');
      buf.writeln('NOTE: This is general context only. For specific '
          'analysis, ask about sales, products, inventory, or request a '
          'business summary.');
      buf.writeln('--- END CONTEXT ---');
    }

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  /// Generates contextual suggested questions based on real database
  /// conditions and the current user's role. Returns only suggestions
  /// relevant to the current state of the business/system and the role's
  /// allowed capabilities.
  Future<List<String>> generateContextualSuggestions() async {
    final role = _sessionManager.currentUser?.role;
    if (role == UserRole.admin) {
      return await _generateAdminSuggestions();
    }
    if (role == UserRole.staff) {
      return await _generateStaffSuggestions();
    }
    return await _generateOwnerSuggestions();
  }

  Future<List<String>> _generateOwnerSuggestions() async {
    final suggestions = <String>[];
    final now = DateTime.now();
    final today = startOfDay(now);

    try {
      // Check for low stock.
      final lowStock = await _productRepository.getLowStockProducts();
      if (lowStock.isNotEmpty) {
        suggestions.add('What should I restock first?');
      }

      // Check today's sales.
      final todaySales = await _saleRepository.getByDateRange(
        today, today.add(const Duration(days: 1)));
      final todayActive = todaySales.where((s) => !s.isDeleted).toList();

      if (todayActive.isEmpty) {
        suggestions.add('Why are there no recorded sales today?');
      } else {
        suggestions.add('How are my sales today?');
      }

      // Check for sales decline (this week vs last week).
      final weekday = now.weekday;
      final thisWeekStart = today.subtract(Duration(days: weekday - 1));
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
      final thisWeekSales = await _saleRepository.getByDateRange(
        thisWeekStart, thisWeekStart.add(const Duration(days: 7)));
      final lastWeekSales = await _saleRepository.getByDateRange(
        lastWeekStart, thisWeekStart);
      final thisWeekTotal =
          thisWeekSales.where((s) => !s.isDeleted).fold<double>(
              0, (sum, s) => sum + s.totalAmount);
      final lastWeekTotal =
          lastWeekSales.where((s) => !s.isDeleted).fold<double>(
              0, (sum, s) => sum + s.totalAmount);

      if (lastWeekTotal > thisWeekTotal && lastWeekTotal > 0) {
        suggestions.add('Why did sales decrease this week?');
      }

      // Always include product performance and summary.
      final products = await _productRepository.getActiveProducts();
      if (products.isNotEmpty) {
        suggestions.add('Which products are performing best?');
      }

      // Check for insufficient history.
      final allSales = await _saleRepository.getAllActive(limit: 10);
      if (allSales.length < 5) {
        suggestions.add('Give me a summary of the sales data available so far.');
      } else {
        suggestions.add('Give me a business summary.');
      }
    } catch (e) {
      _log('generateContextualSuggestions failed: $e');
      // Fallback to basic suggestions.
      suggestions.addAll([
        'How are my sales today?',
        'What should I restock?',
        'Give me a business summary.',
      ]);
    }

    return suggestions;
  }

  Future<List<String>> _generateAdminSuggestions() async {
    final suggestions = <String>[];
    try {
      final users = await _userRepository.getAllActive();
      if (users.isNotEmpty) {
        suggestions.add('How many active users do we have?');
      }

      final recentActivity =
          await _activityLogRepository.getRecentActivities(limit: 1);
      if (recentActivity.isNotEmpty) {
        suggestions.add('Show recent system activity.');
      }

      final backups = await _backupHistoryRepository.getAllActive();
      if (backups.isNotEmpty) {
        suggestions.add('When was the latest backup?');
      } else {
        suggestions.add('Have any backups been created yet?');
      }

      suggestions.add('Give me a system summary.');
    } catch (e) {
      _log('generateAdminSuggestions failed: $e');
      suggestions.addAll([
        'How many active users do we have?',
        'Show recent system activity.',
        'Give me a system summary.',
      ]);
    }
    return suggestions;
  }

  Future<List<String>> _generateStaffSuggestions() async {
    final suggestions = <String>[];
    final userId = _sessionManager.currentUser?.id;
    if (userId == null) return suggestions;

    try {
      final now = DateTime.now();
      final today = startOfDay(now);
      final mySales = await _saleRepository.getByDateRangeAndUser(
        today, today.add(const Duration(days: 1)), userId);
      final myActive = mySales.where((s) => !s.isDeleted).toList();

      if (myActive.isEmpty) {
        suggestions.add('Have I made any sales today?');
      } else {
        suggestions.add('How much did I sell today?');
      }

      final lowStock = await _productRepository.getLowStockProducts();
      if (lowStock.isNotEmpty) {
        suggestions.add('What products are low in stock?');
      }

      suggestions.add('Show my recent sales.');
      suggestions.add('Which products sell best in my transactions?');
    } catch (e) {
      _log('generateStaffSuggestions failed: $e');
      suggestions.addAll([
        'How much did I sell today?',
        'What products are low in stock?',
        'Show my recent sales.',
      ]);
    }
    return suggestions;
  }

  // ── Admin intent detection ───────────────────────────────────────────

  DetectedIntent _detectAdminIntent(
    String q,
    DateTime? startDate,
    DateTime? endDate,
    String? periodDesc,
  ) {
    // User account summaries
    if (_matches(q, ['active user', 'how many user', 'user count',
        'number of user', 'user summary', 'users do we have'])) {
      return DetectedIntent(
        intent: BusinessIntent.activeUserSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // User status (active/inactive)
    if (_matches(q, ['user status', 'inactive user', 'disabled user',
        'enabled user', 'who is active', 'who is inactive'])) {
      return DetectedIntent(
        intent: BusinessIntent.userStatusSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // System activity summary
    if (_matches(q, ['system activity', 'activity summary',
        'today\'s activity', 'administrative activity',
        'summarize activity', 'activity today'])) {
      return DetectedIntent(
        intent: BusinessIntent.systemActivitySummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Recent activity
    if (_matches(q, ['recent activity', 'show activity',
        'latest activity', 'what happened', 'failed activity',
        'critical activity', 'unusual activity', 'error activity'])) {
      return DetectedIntent(
        intent: BusinessIntent.recentActivity,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Backup summary
    if (_matches(q, ['backup', 'latest backup', 'last backup',
        'when was the backup', 'backup history', 'backup status'])) {
      return DetectedIntent(
        intent: BusinessIntent.backupSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Export summary
    if (_matches(q, ['export', 'export history', 'exported report',
        'what was exported', 'export status'])) {
      return DetectedIntent(
        intent: BusinessIntent.exportSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // System status summary
    if (_matches(q, ['system status', 'system health',
        'system overview', 'is the system', 'system configuration'])) {
      return DetectedIntent(
        intent: BusinessIntent.systemStatusSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Admin summary / overview
    if (_matches(q, ['admin summary', 'system summary',
        'give me a summary', 'overview', 'summarize today',
        'what should i focus', 'recommendations', 'what should i do'])) {
      return DetectedIntent(
        intent: BusinessIntent.adminSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    return DetectedIntent(
      intent: BusinessIntent.general,
      startDate: startDate,
      endDate: endDate,
      periodDescription: periodDesc,
    );
  }

  // ── Staff intent detection ───────────────────────────────────────────

  DetectedIntent _detectStaffIntent(
    String q,
    DateTime? startDate,
    DateTime? endDate,
    String? periodDesc,
  ) {
    // My sales (own sales only, filtered by currentUserId)
    if (_matches(q, ['my sales', 'how much did i sell', 'how much did i make',
        'i sell today', 'i make today', 'my transactions',
        'how am i doing', 'how did i do']) ||
        (q.contains('i sell') && (q.contains('today') ||
            q.contains('week') || q.contains('month')))) {
      if (periodDesc == 'today' || q.contains('today')) {
        return DetectedIntent(
          intent: BusinessIntent.myTodaySales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      return DetectedIntent(
        intent: BusinessIntent.myDateRangeSales,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // My recent sales
    if (_matches(q, ['recent sales', 'show my sales',
        'my recent sales', 'latest sales', 'recent transactions'])) {
      return DetectedIntent(
        intent: BusinessIntent.myRecentSales,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // My top sold products (in my transactions)
    if (_matches(q, ['best in my', 'my top', 'my best selling',
        'sell best in my', 'selling best in my',
        'what products sell best in my', 'my transactions'])) {
      return DetectedIntent(
        intent: BusinessIntent.myTopSoldProducts,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Low stock (shared intent — Staff can view stock)
    if (_matches(q, ['low stock', 'low on stock', 'running low',
        'out of stock', 'stock level', 'below minimum'])) {
      return DetectedIntent(
        intent: BusinessIntent.lowStock,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Product information
    if (_matches(q, ['product information', 'tell me about product',
        'what products', 'product list', 'show products',
        'how many products'])) {
      return DetectedIntent(
        intent: BusinessIntent.productInformation,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Category information
    if (_matches(q, ['category information', 'tell me about category',
        'what categories', 'category list', 'show categories',
        'how many categories'])) {
      return DetectedIntent(
        intent: BusinessIntent.categoryInformation,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // My activity summary
    if (_matches(q, ['my activity', 'what have i done',
        'my work activity', 'my actions'])) {
      return DetectedIntent(
        intent: BusinessIntent.myActivitySummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // My work summary / overview
    if (_matches(q, ['my work summary', 'my summary', 'give me a summary',
        'overview', 'how is my work', 'what should i do',
        'help me with', 'advice'])) {
      return DetectedIntent(
        intent: BusinessIntent.myWorkSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    return DetectedIntent(
      intent: BusinessIntent.general,
      startDate: startDate,
      endDate: endDate,
      periodDescription: periodDesc,
    );
  }

  // ── Admin data gathering ─────────────────────────────────────────────
  //
  // Each method queries ONLY the approved Admin data domains (users,
  // activity_logs, backup_history, export_history). Never exposes
  // password_hash, pin, API keys, or business sales/products/inventory.

  Future<BusinessFacts> _gatherActiveUserSummary(DetectedIntent d) async {
    final users = await _userRepository.getAllActive();
    final activeCount = users.where((u) => u.isActive).length;
    final inactiveCount = users.length - activeCount;

    // Count by role.
    final owners = users.where((u) => u.role == UserRole.owner).length;
    final admins = users.where((u) => u.role == UserRole.admin).length;
    final staff = users.where((u) => u.role == UserRole.staff).length;

    final buf = StringBuffer();
    buf.writeln('--- ACTIVE USER SUMMARY ---');
    buf.writeln('Total users (not soft-deleted): ${users.length}');
    buf.writeln('Active: $activeCount');
    buf.writeln('Inactive: $inactiveCount');
    buf.writeln('');
    buf.writeln('By role:');
    buf.writeln('  Owners: $owners');
    buf.writeln('  Admins: $admins');
    buf.writeln('  Staff: $staff');
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherUserStatusSummary(DetectedIntent d) async {
    final users = await _userRepository.getAllActive();
    final active = users.where((u) => u.isActive).toList();
    final inactive = users.where((u) => !u.isActive).toList();

    final buf = StringBuffer();
    buf.writeln('--- USER STATUS SUMMARY ---');
    buf.writeln('Active users (${active.length}):');
    for (final u in active.take(20)) {
      buf.writeln('  - ${u.fullName} (${u.role.displayName}) — '
          'last login: ${u.lastLogin != null ? _formatDateTime(u.lastLogin!) : 'never'}');
    }
    if (inactive.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Inactive users (${inactive.length}):');
      for (final u in inactive.take(10)) {
        buf.writeln('  - ${u.fullName} (${u.role.displayName})');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherSystemActivitySummary(DetectedIntent d) async {
    final now = DateTime.now();
    final today = startOfDay(now);
    final activities = await _activityLogRepository.getByDateRange(
      today, today.add(const Duration(days: 1)), limit: 100);

    // Group by action type.
    final actionCounts = <String, int>{};
    for (final a in activities) {
      actionCounts[a.action] = (actionCounts[a.action] ?? 0) + 1;
    }

    final buf = StringBuffer();
    buf.writeln('--- SYSTEM ACTIVITY SUMMARY (today) ---');
    buf.writeln('Total activities today: ${activities.length}');
    if (actionCounts.isNotEmpty) {
      buf.writeln('');
      buf.writeln('By action type:');
      final sorted = actionCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buf.writeln('  - ${e.key}: ${e.value}');
      }
    }
    // Check for failed/unusual activities.
    final failed = activities.where((a) =>
        a.action.contains('fail') ||
        a.action.contains('error') ||
        a.action.contains('unauthorized') ||
        a.action.contains('denied')).toList();
    if (failed.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Failed/unusual activities: ${failed.length}');
      for (final f in failed.take(10)) {
        buf.writeln('  - ${f.action}: ${f.details ?? 'no details'} '
            '(${_formatDateTime(f.createdAt)})');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherRecentActivity(DetectedIntent d) async {
    final activities =
        await _activityLogRepository.getRecentActivities(limit: 20);

    final buf = StringBuffer();
    buf.writeln('--- RECENT SYSTEM ACTIVITY ---');
    if (activities.isEmpty) {
      buf.writeln('No recent activities recorded.');
    } else {
      for (final a in activities) {
        buf.writeln('  - ${_formatDateTime(a.createdAt)}: ${a.action}'
            '${a.entity != null ? ' on ${a.entity}' : ''}'
            '${a.details != null ? ' — ${a.details}' : ''}');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: activities.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherBackupSummary(DetectedIntent d) async {
    final backups = await _backupHistoryRepository.getAllActive();

    final buf = StringBuffer();
    buf.writeln('--- BACKUP SUMMARY ---');
    buf.writeln('Total backups: ${backups.length}');
    if (backups.isNotEmpty) {
      final latest = backups.first;
      buf.writeln('Latest backup: ${_formatDateTime(latest.createdAt)}');
      if (latest.fileSize != null) {
        buf.writeln('Latest backup size: ${_formatFileSize(latest.fileSize!)}');
      }
      // Backups in last 7 days.
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final recentBackups =
          backups.where((b) => b.createdAt.isAfter(weekAgo)).length;
      buf.writeln('Backups in last 7 days: $recentBackups');
      // List recent backups.
      buf.writeln('');
      buf.writeln('Recent backups:');
      for (final b in backups.take(5)) {
        buf.writeln('  - ${_formatDateTime(b.createdAt)}'
            '${b.fileSize != null ? ' (${_formatFileSize(b.fileSize!)})' : ''}');
      }
    } else {
      buf.writeln('No backups have been created yet.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: backups.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherExportSummary(DetectedIntent d) async {
    final exports = await _exportHistoryRepository.getAllActive();

    final buf = StringBuffer();
    buf.writeln('--- EXPORT SUMMARY ---');
    buf.writeln('Total exports: ${exports.length}');
    if (exports.isNotEmpty) {
      final latest = exports.first;
      buf.writeln('Latest export: ${_formatDateTime(latest.createdAt)}');
      buf.writeln('Latest export type: ${latest.reportType}'
          ' (${latest.fileFormat})');
      // Exports in last 7 days.
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final recentExports =
          exports.where((e) => e.createdAt.isAfter(weekAgo)).length;
      buf.writeln('Exports in last 7 days: $recentExports');
      // Group by report type.
      final typeCounts = <String, int>{};
      for (final e in exports) {
        typeCounts[e.reportType] = (typeCounts[e.reportType] ?? 0) + 1;
      }
      buf.writeln('');
      buf.writeln('By report type:');
      for (final entry in typeCounts.entries) {
        buf.writeln('  - ${entry.key}: ${entry.value}');
      }
    } else {
      buf.writeln('No exports have been created yet.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: exports.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherSystemStatusSummary(DetectedIntent d) async {
    final users = await _userRepository.getAllActive();
    final backups = await _backupHistoryRepository.getAllActive();
    final exports = await _exportHistoryRepository.getAllActive();
    final now = DateTime.now();
    final today = startOfDay(now);
    final todayActivities = await _activityLogRepository.getByDateRange(
      today, today.add(const Duration(days: 1)), limit: 500);

    final buf = StringBuffer();
    buf.writeln('--- SYSTEM STATUS SUMMARY ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('');
    buf.writeln('USERS:');
    buf.writeln('  Total: ${users.length}');
    buf.writeln('  Active: ${users.where((u) => u.isActive).length}');
    buf.writeln('  Inactive: ${users.where((u) => !u.isActive).length}');
    buf.writeln('');
    buf.writeln('ACTIVITY TODAY:');
    buf.writeln('  Total activities: ${todayActivities.length}');
    final failed = todayActivities.where((a) =>
        a.action.contains('fail') ||
        a.action.contains('error') ||
        a.action.contains('unauthorized') ||
        a.action.contains('denied')).length;
    buf.writeln('  Failed/unusual: $failed');
    buf.writeln('');
    buf.writeln('BACKUPS:');
    buf.writeln('  Total: ${backups.length}');
    if (backups.isNotEmpty) {
      buf.writeln('  Latest: ${_formatDateTime(backups.first.createdAt)}');
    }
    buf.writeln('');
    buf.writeln('EXPORTS:');
    buf.writeln('  Total: ${exports.length}');
    if (exports.isNotEmpty) {
      buf.writeln('  Latest: ${_formatDateTime(exports.first.createdAt)}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherAdminSummary(DetectedIntent d) async {
    // Comprehensive admin overview.
    final users = await _userRepository.getAllActive();
    final backups = await _backupHistoryRepository.getAllActive();
    final exports = await _exportHistoryRepository.getAllActive();
    final recentActivity =
        await _activityLogRepository.getRecentActivities(limit: 10);
    final now = DateTime.now();
    final today = startOfDay(now);
    final todayActivities = await _activityLogRepository.getByDateRange(
      today, today.add(const Duration(days: 1)), limit: 200);

    final buf = StringBuffer();
    buf.writeln('--- ADMIN SUMMARY ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('');
    buf.writeln('USERS:');
    buf.writeln('  Total: ${users.length}');
    buf.writeln('  Active: ${users.where((u) => u.isActive).length}');
    buf.writeln('');
    buf.writeln('ACTIVITY TODAY: ${todayActivities.length} activities');
    final failed = todayActivities.where((a) =>
        a.action.contains('fail') ||
        a.action.contains('error') ||
        a.action.contains('unauthorized') ||
        a.action.contains('denied')).toList();
    if (failed.isNotEmpty) {
      buf.writeln('  Failed/unusual: ${failed.length}');
      for (final f in failed.take(5)) {
        buf.writeln('    - ${f.action}: ${f.details ?? 'no details'}');
      }
    }
    buf.writeln('');
    buf.writeln('RECENT ACTIVITY:');
    for (final a in recentActivity.take(5)) {
      buf.writeln('  - ${a.action}'
          '${a.entity != null ? ' on ${a.entity}' : ''}');
    }
    buf.writeln('');
    buf.writeln('BACKUPS: ${backups.length} total');
    if (backups.isNotEmpty) {
      buf.writeln('  Latest: ${_formatDateTime(backups.first.createdAt)}');
    }
    buf.writeln('EXPORTS: ${exports.length} total');
    buf.writeln('--- END SUMMARY ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  // ── Staff data gathering (filtered by currentUserId) ─────────────────
  //
  // All Staff sales queries use getByDateRangeAndUser / getByUserId which
  // enforce sales.user_id = currentUserId at the SQL level. The AI never
  // chooses the user ID — it comes from the authenticated session.

  Future<BusinessFacts> _gatherMyTodaySales(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    final now = DateTime.now();
    final today = startOfDay(now);
    // SQL-level filter: sales.user_id = userId
    final sales = await _saleRepository.getByDateRangeAndUser(
      today, today.add(const Duration(days: 1)), userId);
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final total =
        activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count = activeSales.length;
    final avg = count > 0 ? total / count : 0.0;

    // Yesterday comparison (own sales).
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdaySales = await _saleRepository.getByDateRangeAndUser(
      yesterday, today, userId);
    final yesterdayActive =
        yesterdaySales.where((s) => !s.isDeleted).toList();
    final yesterdayTotal =
        yesterdayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);

    final change = yesterdayTotal > 0
        ? ((total - yesterdayTotal) / yesterdayTotal) * 100
        : null;

    final buf = StringBuffer();
    buf.writeln('--- YOUR SALES TODAY ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('Your total sales today: PHP ${_formatMoney(total)}');
    buf.writeln('Your transactions today: $count');
    buf.writeln('Your average transaction: PHP ${_formatMoney(avg)}');
    buf.writeln('');
    buf.writeln('Your sales yesterday (${_formatDate(yesterday)}):');
    buf.writeln('  Total: PHP ${_formatMoney(yesterdayTotal)}');
    buf.writeln('  Transactions: ${yesterdayActive.length}');
    if (change != null) {
      buf.writeln('  Change: ${change >= 0 ? '+' : ''}'
          '${change.toStringAsFixed(1)}%');
    }
    if (count == 0) {
      buf.writeln('');
      buf.writeln('NOTE: You have not made any sales today yet.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  Future<BusinessFacts> _gatherMyDateRangeSales(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    final start =
        d.startDate ?? DateTime.now().subtract(const Duration(days: 7));
    final end = d.endDate ?? DateTime.now().add(const Duration(days: 1));
    // SQL-level filter: sales.user_id = userId
    final sales =
        await _saleRepository.getByDateRangeAndUser(start, end, userId);
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final total =
        activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final count = activeSales.length;
    final avg = count > 0 ? total / count : 0.0;

    final buf = StringBuffer();
    buf.writeln('--- YOUR SALES (${d.periodDescription ?? 'custom range'}) ---');
    buf.writeln('Period: ${_formatDate(start)} to ${_formatDate(end)}');
    buf.writeln('Your total sales: PHP ${_formatMoney(total)}');
    buf.writeln('Your transactions: $count');
    buf.writeln('Your average transaction: PHP ${_formatMoney(avg)}');
    if (count == 0) {
      buf.writeln('NOTE: You did not make any sales in this period.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: count > 0,
    );
  }

  Future<BusinessFacts> _gatherMyRecentSales(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    // SQL-level filter: sales.user_id = userId
    final sales = await _saleRepository.getByUserId(userId, limit: 10);
    final activeSales = sales.where((s) => !s.isDeleted).toList();

    final buf = StringBuffer();
    buf.writeln('--- YOUR RECENT SALES ---');
    if (activeSales.isEmpty) {
      buf.writeln('You have not made any sales yet.');
    } else {
      for (final s in activeSales) {
        buf.writeln('  - ${_formatDateTime(s.createdAt)}: '
            'PHP ${_formatMoney(s.totalAmount)}');
      }
      buf.writeln('');
      buf.writeln('Total recent transactions: ${activeSales.length}');
      final total =
          activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
      buf.writeln('Total value: PHP ${_formatMoney(total)}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: activeSales.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherMyTopSoldProducts(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    // SQL-level filter: s.user_id = userId (passed to DAO)
    final topProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 10,
      since: d.startDate,
      userId: userId,
    );

    final buf = StringBuffer();
    buf.writeln('--- YOUR TOP-SELLING PRODUCTS '
        '(${d.periodDescription ?? 'all time'}) ---');
    if (topProducts.isEmpty) {
      buf.writeln('No sales data available for your transactions.');
    } else {
      for (var i = 0; i < topProducts.length; i++) {
        final p = topProducts[i];
        buf.writeln('${i + 1}. ${p['product_name']} — '
            '${p['total_quantity']} units sold by you');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: topProducts.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherProductInformation(DetectedIntent d) async {
    final products = await _productRepository.getActiveProducts();

    final buf = StringBuffer();
    buf.writeln('--- PRODUCT INFORMATION ---');
    buf.writeln('Total active products: ${products.length}');
    if (products.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Products:');
      for (final p in products.take(20)) {
        buf.writeln('  - ${p.name}: PHP ${_formatMoney(p.price)}, '
            'stock: ${p.stock} units');
      }
      if (products.length > 20) {
        buf.writeln('  ... and ${products.length - 20} more.');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: products.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherCategoryInformation(DetectedIntent d) async {
    final categories = await _categoryRepository.getActiveCategories();

    final buf = StringBuffer();
    buf.writeln('--- CATEGORY INFORMATION ---');
    buf.writeln('Total active categories: ${categories.length}');
    if (categories.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Categories:');
      for (final c in categories) {
        buf.writeln('  - ${c.name}'
            '${c.description.isNotEmpty
                ? ': ${c.description}' : ''}');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: categories.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherMyActivitySummary(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    final activities =
        await _activityLogRepository.getByUserId(userId);
    final recent = activities.take(15).toList();

    final buf = StringBuffer();
    buf.writeln('--- YOUR ACTIVITY SUMMARY ---');
    buf.writeln('Total your activities: ${activities.length}');
    if (recent.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Your recent activities:');
      for (final a in recent) {
        buf.writeln('  - ${_formatDateTime(a.createdAt)}: ${a.action}'
            '${a.entity != null ? ' on ${a.entity}' : ''}');
      }
    } else {
      buf.writeln('No activities recorded for your account.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: activities.isNotEmpty,
    );
  }

  Future<BusinessFacts> _gatherMyWorkSummary(
      DetectedIntent d, int? userId) async {
    if (userId == null) {
      return _noUserData(d);
    }
    final now = DateTime.now();
    final today = startOfDay(now);
    // SQL-level filter: sales.user_id = userId
    final todaySales = await _saleRepository.getByDateRangeAndUser(
      today, today.add(const Duration(days: 1)), userId);
    final todayActive = todaySales.where((s) => !s.isDeleted).toList();
    final todayTotal =
        todayActive.fold<double>(0, (sum, s) => sum + s.totalAmount);

    // My top products (last 7 days).
    final myTopProducts = await _saleItemDao.getTopProductsByQuantity(
      limit: 5,
      since: now.subtract(const Duration(days: 7)),
      userId: userId,
    );

    // Low stock.
    final lowStock = await _productRepository.getLowStockProducts();

    // My recent activity.
    final myActivities =
        await _activityLogRepository.getByUserId(userId);
    final todayActivities = myActivities
        .where((a) => a.createdAt.isAfter(today))
        .length;

    final buf = StringBuffer();
    buf.writeln('--- YOUR WORK SUMMARY ---');
    buf.writeln('Date: ${_formatDate(today)}');
    buf.writeln('');
    buf.writeln('YOUR SALES TODAY:');
    buf.writeln('  Total: PHP ${_formatMoney(todayTotal)}'
        ' (${todayActive.length} transactions)');
    buf.writeln('');
    buf.writeln('YOUR TOP PRODUCTS (last 7 days):');
    if (myTopProducts.isEmpty) {
      buf.writeln('  No sales in the last 7 days.');
    } else {
      for (var i = 0; i < myTopProducts.length; i++) {
        final p = myTopProducts[i];
        buf.writeln('  ${i + 1}. ${p['product_name']} — '
            '${p['total_quantity']} units');
      }
    }
    buf.writeln('');
    buf.writeln('LOW STOCK ITEMS: ${lowStock.length}');
    if (lowStock.isNotEmpty) {
      for (final p in lowStock.take(5)) {
        buf.writeln('  - ${p.name}: ${p.stock} units (min: ${p.minStock})');
      }
    }
    buf.writeln('');
    buf.writeln('YOUR ACTIVITIES TODAY: $todayActivities');
    buf.writeln('--- END SUMMARY ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  /// Returns a "no user data" fact when the current user ID is missing.
  BusinessFacts _noUserData(DetectedIntent d) {
    return BusinessFacts(
      context: 'Unable to identify the current user. Please try again.',
      intent: d.intent,
      hasData: false,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  bool _matches(String query, List<String> patterns) {
    return patterns.any((p) => query.contains(p));
  }

  DateTime _startOfWeek() {
    final now = DateTime.now();
    final today = startOfDay(now);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[BusinessIntelligenceService] $message');
    }
  }
}
