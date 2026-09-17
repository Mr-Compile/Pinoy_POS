import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
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
  recentSales,
  staffSales,
  // ── Admin / system-administrative intents ──
  activeUserSummary,
  userStatusSummary,
  systemActivitySummary,
  recentActivity,
  backupSummary,
  exportSummary,
  systemStatusSummary,
  adminSummary,
  userLookup,
  // ── Staff / own-data intents (filtered by currentUserId) ──
  myTodaySales,
  myDateRangeSales,
  myRecentSales,
  myTopSoldProducts,
  productInformation,
  categoryInformation,
  myActivitySummary,
  myWorkSummary,
  // ── Entity lookups (Owner + Staff; Staff results are scoped to the
  // user's own records) ──
  productLookup,
  saleLookup,
  paymentBreakdown,
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
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
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
    // Normalize first: punctuation stripped and misspelled tokens
    // snapped to the intent vocabulary, so "saels", "staf sales",
    // and "who's my employe" still reach the right intent.
    final q = _normalizeQuery(query);

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

    // Specific sale/receipt lookup — "receipt 20260908-0001",
    // "what was sale #42", "what was my latest transaction". Checked
    // before the payment-split and generic sales blocks because it
    // carries an explicit reference that must not be absorbed by either.
    if (_containsSaleReference(q)) {
      return DetectedIntent(
        intent: BusinessIntent.saleLookup,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Payment-method split ("GCash vs cash sales today", "how much did we
    // make in GCash?"). Checked before the generic sales block so phrases
    // like 'gcash sales today' are not swallowed by todaySales.
    if (_mentionsPaymentMethodSplit(q)) {
      return DetectedIntent(
        intent: BusinessIntent.paymentBreakdown,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Recent transactions list.
    if (_matches(q, ['recent sales', 'latest sales', 'recent transactions',
        'latest transactions', 'show recent sales', 'show latest sales'])) {
      return DetectedIntent(
        intent: BusinessIntent.recentSales,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Specific product lookup — "price of coke", "magkano ang coke",
    // "stock of lucky me". Generic terms ("products", "stock") are
    // filtered inside _extractProductCandidate.
    if (extractProductCandidate(q) != null) {
      return DetectedIntent(
        intent: BusinessIntent.productLookup,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Staff & user accounts — the owner can see every account plus
    // per-staff sales performance. Placed before the generic sales
    // block so 'staff sales today' resolves to staffSales instead of
    // being absorbed by business-wide todaySales.
    final asksAboutPerson = _matches(q, ['who is', "who's", 'whos']) ||
        _staffAccountPattern.hasMatch(q);
    if (asksAboutPerson) {
      // Per-staff performance — "staff sales today", "which staff
      // sold the most", "my best employee".
      if (_matches(q, ['sale', 'sold', 'revenue', 'income', 'earning',
          'performance', 'best', 'top', 'most', 'highest'])) {
        return DetectedIntent(
          intent: BusinessIntent.staffSales,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      // Named-account lookup — "who is maria".
      if (_extractUserCandidate(q) != null) {
        return DetectedIntent(
          intent: BusinessIntent.userLookup,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      // Headcount — "how many staff", "how many users".
      if (_matches(q, ['how many', 'count', 'number of', 'total '])) {
        return DetectedIntent(
          intent: BusinessIntent.activeUserSummary,
          startDate: startDate,
          endDate: endDate,
          periodDescription: periodDesc,
        );
      }
      // Full roster — "who are my staff", "list users", "my team".
      return DetectedIntent(
        intent: BusinessIntent.userStatusSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

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

    // System administration data — the owner can see everything:
    // audit activity, backups, exports, and system status.
    if (_matches(q, ['backup'])) {
      return DetectedIntent(
        intent: BusinessIntent.backupSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }
    if (_matches(q, ['export'])) {
      return DetectedIntent(
        intent: BusinessIntent.exportSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }
    if (_matches(q, ['system status', 'system health', 'system overview',
        'system summary', 'system configuration'])) {
      return DetectedIntent(
        intent: BusinessIntent.systemStatusSummary,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }
    if (_matches(q, ['activity', 'audit log', 'what happened'])) {
      return DetectedIntent(
        intent: _matches(q, ['recent', 'latest', 'show', 'log'])
            ? BusinessIntent.recentActivity
            : BusinessIntent.systemActivitySummary,
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
  ///
  /// For sales-related intents, an AUDIT SIGNALS block computed from the
  /// last 28 days (baseline mean, standard deviation, z-score of today's
  /// total, same-weekday comparison, payment-mix shift) is appended to
  /// the context so the AI can flag real anomalies instead of guessing.
  Future<BusinessFacts> gatherFacts(
    DetectedIntent detected, {
    UserRole? role,
    int? userId,
    String? query,
  }) async {
    final facts =
        await _dispatchFacts(detected, role: role, userId: userId, query: query);
    if (!_auditIntents.contains(detected.intent)) return facts;
    try {
      final audit = await _buildAuditSignals(role: role, userId: userId);
      if (audit.isEmpty) return facts;
      return BusinessFacts(
        context: '${facts.context}\n$audit',
        intent: facts.intent,
        hasData: facts.hasData,
      );
    } catch (e) {
      _log('Audit signals failed for intent ${detected.intent}: $e');
      return facts;
    }
  }

  /// Intents that receive a computed audit block appended to their facts.
  static const Set<BusinessIntent> _auditIntents = {
    BusinessIntent.todaySales,
    BusinessIntent.yesterdaySales,
    BusinessIntent.dateRangeSales,
    BusinessIntent.weeklySales,
    BusinessIntent.monthlySales,
    BusinessIntent.salesComparison,
    BusinessIntent.businessSummary,
    BusinessIntent.trendAnalysis,
    BusinessIntent.busiestPeriod,
    BusinessIntent.myTodaySales,
    BusinessIntent.myDateRangeSales,
    BusinessIntent.myRecentSales,
    BusinessIntent.myWorkSummary,
  };

  Future<BusinessFacts> _dispatchFacts(
    DetectedIntent detected, {
    UserRole? role,
    int? userId,
    String? query,
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
        case BusinessIntent.recentSales:
          return await _gatherRecentSales(detected);
        case BusinessIntent.staffSales:
          return await _gatherStaffSales(detected);
        // ── Entity lookups (role-scoped inside each gather) ──
        case BusinessIntent.productLookup:
          return await _gatherProductLookup(detected, query: query);
        case BusinessIntent.saleLookup:
          return await _gatherSaleLookup(
            detected,
            role: role,
            userId: userId,
            query: query,
          );
        case BusinessIntent.paymentBreakdown:
          return await _gatherPaymentBreakdown(
            detected,
            role: role,
            userId: userId,
          );
        case BusinessIntent.userLookup:
          return await _gatherUserLookup(detected, query: query);
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
          return await _gatherGeneralContext(
            detected,
            role: role,
            userId: userId,
            query: query,
          );
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
    final topProducts = await _saleItemRepository.getTopProducts(
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
    final topProducts = await _saleItemRepository.getTopProducts(
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
    final topProducts = await _saleItemRepository.getTopProducts(
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
    final recentSales = await _saleItemRepository.getTopProducts(
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
    final topProducts = await _saleItemRepository.getTopProducts(
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

    // Group by day of week with Sunday as the first day.
    final dayTotals = <int, double>{};
    final dayCounts = <int, int>{};
    for (final s in activeSales) {
      final weekday = s.createdAt.weekday % 7;
      dayTotals[weekday] = (dayTotals[weekday] ?? 0) + s.totalAmount;
      dayCounts[weekday] = (dayCounts[weekday] ?? 0) + 1;
    }

    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final buf = StringBuffer();
    buf.writeln('--- BUSIEST PERIOD DATA (last 30 days) ---');
    buf.writeln('Total transactions in last 30 days: ${activeSales.length}');
    if (activeSales.isEmpty) {
      buf.writeln('No sales data available for the last 30 days.');
    } else {
      buf.writeln('Sales by day of week:');
      for (var i = 0; i < 7; i++) {
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
    final topProducts = await _saleItemRepository.getTopProducts(
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

  /// Business-wide recent transactions (Owner). Each line carries the
  /// receipt number, time, total, payment method, and the cashier's name
  /// so the AI can answer "who handled that sale" style follow-ups.
  Future<BusinessFacts> _gatherRecentSales(DetectedIntent d) async {
    final sales = await _saleRepository.getAllActive(limit: 10);
    final active = sales.where((s) => !s.isDeleted).toList();

    // Resolve cashier names (one lookup per distinct user id).
    final names = <int, String>{};
    for (final s in active) {
      if (!names.containsKey(s.userId)) {
        final u = await _userRepository.getById(s.userId);
        names[s.userId] = u?.fullName ?? 'User ${s.userId}';
      }
    }

    final buf = StringBuffer();
    buf.writeln('--- RECENT SALES (business-wide) ---');
    if (active.isEmpty) {
      buf.writeln('No sales have been recorded yet.');
    } else {
      for (final s in active) {
        buf.writeln('  - ${s.receiptNumber ?? 'Sale #${s.id}'} · '
            '${_formatDateTime(s.createdAt)} · '
            'PHP ${_formatMoney(s.totalAmount)} · '
            '${s.paymentMethod} · ${s.paymentStatus} · '
            'by ${names[s.userId]}'
            '${s.customerName != null && s.customerName!.isNotEmpty ? ' · customer: ${s.customerName}' : ''}');
      }
      buf.writeln('');
      buf.writeln('Showing the ${active.length} most recent sales.');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: active.isNotEmpty,
    );
  }

  /// Per-staff sales performance for the period — "which staff sold
  /// the most today", "employee sales this week". Business-wide by
  /// design: the owner sees every user's contribution.
  Future<BusinessFacts> _gatherStaffSales(DetectedIntent d) async {
    final now = DateTime.now();
    final start = d.startDate ?? startOfDay(now);
    final end = d.endDate ?? start.add(const Duration(days: 1));
    final staff = await _saleRepository.getStaffSalesSummary(start, end);
    final ranked = staff.toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    final buf = StringBuffer();
    buf.writeln('--- STAFF SALES PERFORMANCE '
        '(${d.periodDescription ?? 'today'}) ---');
    buf.writeln('Period: ${_formatDate(start)} to ${_formatDate(end)}');
    if (ranked.isEmpty) {
      buf.writeln('No sales recorded by any staff in this period.');
    } else {
      var rank = 1;
      for (final s in ranked.take(20)) {
        buf.writeln('  $rank. ${s.fullName}'
            '${s.role != null ? ' (${s.role!.displayName})' : ''} — '
            'PHP ${_formatMoney(s.totalSales)} '
            '(${s.transactionCount} transactions, '
            'avg PHP ${_formatMoney(s.averageTransaction)})');
        rank++;
      }
      final total =
          ranked.fold<double>(0, (sum, s) => sum + s.totalSales);
      buf.writeln('');
      buf.writeln('Total staff sales: PHP ${_formatMoney(total)}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: ranked.isNotEmpty,
    );
  }

  // ── Entity lookups ──────────────────────────────────────────────────
  //
  // These intents resolve a specific entity named in the query (product,
  // sale/receipt, user account) against the database and return real
  // field values. Results are role-scoped: Staff sale lookups only see
  // their own sales; Admin user lookups only run for the admin role.

  /// Phrases that introduce a product name, e.g. "price of coke",
  /// "magkano ang coke", "stock of lucky me".
  static const _productLookupPrefixes = [
    'price of',
    'price for',
    'how much is',
    'how much does',
    'how much for',
    'how much',
    'cost of',
    'cost for',
    'stock of',
    'stocks of',
    'stock level of',
    'stock for',
    'inventory of',
    'how many',
    'do we have',
    'do we still have',
    'do you have',
    'do you still have',
    'still have',
    'any more',
    'check',
    'find',
    'search for',
    'look up',
    'lookup',
    'magkano ang',
    'magkano ba ang',
    'magkano po ang',
    'magkano',
    'presyo ng',
    'presyo nang',
    'presyo',
    'ilan pa ang',
    'ilan pa',
    'ilan na',
    'ilan',
  ];

  /// Words that mean the question is about a whole domain rather than a
  /// named entity ("how many products do we have" → productInformation,
  /// not a lookup for "products").
  static const _genericLookupTerms = {
    'product',
    'products',
    'item',
    'items',
    'stock',
    'stocks',
    'inventory',
    'category',
    'categories',
    'sale',
    'sales',
    'transaction',
    'transactions',
    'order',
    'orders',
    'user',
    'users',
    'account',
    'accounts',
    'count',
    'list',
    'summary',
    'status',
    'settings',
    'management',
    'everything',
    'anything',
    'it',
    'this',
    'that',
    'them',
    'money',
    'cash',
    'gcash',
    'all',
  };

  /// Trailing filler words stripped from a lookup candidate, e.g.
  /// "how many coke do we have" → "coke".
  static final _lookupFillerSuffix = RegExp(
    r'\s+(cost|left|available|in stock|in store|in the store|in the shop|'
    r'in shop|stock|please|po|ba|nga|today|now|na|pa|do we have|'
    r'do you have|on hand|remaining|selling|for sale|meron pa)\.?$',
    caseSensitive: false,
  );

  /// Extracts the entity name the user is asking about, or null when the
  /// query does not use a lookup phrase or the candidate is a generic
  /// domain word.
  /// Words that mark a question or verb phrase rather than a product
  /// name. A candidate containing any of these is the tail of a sentence
  /// like "how much did i sell today" — not something the user is asking
  /// the catalog about.
  static const _nonProductWords = {
    'did',
    'do',
    'does',
    'is',
    'are',
    'was',
    'were',
    'am',
    'i',
    'you',
    'they',
    'it',
    'he',
    'she',
    'sell',
    'sold',
    'make',
    'made',
    'earn',
    'earned',
    'get',
    'got',
    'take',
    'took',
    'have',
    'has',
    'had',
    'will',
    'would',
    'should',
    'could',
    'much',
    'many',
    'cost',
    'left',
    'there',
    'this',
    'that',
    'who',
    'what',
    'when',
    'where',
    'why',
    'how',
    'total',
    'profit',
    'revenue',
    'income',
    // People words — "how many staff ko" is a staff question, never a
    // lookup for a product called "staff ko".
    'staff',
    'employee',
    'employees',
    'member',
    'members',
    'team',
    'user',
    'users',
    'account',
    'accounts',
    'ko',
    'aking',
    'natin',
    'namin',
  };

  static String? extractProductCandidate(String query) {
    final q = query.toLowerCase().trim();
    for (final prefix in _productLookupPrefixes) {
      // Prefix must be followed by a space so 'is' can't match 'island'.
      if (!q.startsWith('$prefix ')) continue;
      var rest = q.substring(prefix.length).trim();
      rest = rest.replaceAll(RegExp(r'[?.!]+$'), '').trim();
      // Strip trailing filler repeatedly ("coke in stock please" → "coke").
      while (true) {
        final stripped = rest.replaceAll(_lookupFillerSuffix, '').trim();
        if (stripped == rest) break;
        rest = stripped;
      }
      // Strip leading articles/fillers ("the", "ang").
      rest = rest
          .replaceAll(RegExp(r'^(the|a|an|ang|yung|si|sa)\s+'), '')
          .trim();
      if (rest.isEmpty) return null;
      if (_genericLookupTerms.contains(rest)) return null;
      // Reject verb/pronoun phrases — "how much did i sell" is a sales
      // question, not a lookup for a product called "did i sell".
      final words = rest.split(RegExp(r'\s+'));
      if (words.any(_nonProductWords.contains)) return null;
      return rest;
    }
    return null;
  }

  /// Phrases that introduce a user account name for the Admin lookup.
  static const _userLookupPrefixes = [
    'who is',
    "who's",
    'whos',
    'tell me about',
    'show user',
    'show account',
    'find user',
    'find account',
    'find',
    'search for',
    'look up',
    'lookup',
    'about user',
    'about the user',
    'about',
    'user account',
    'account of',
    'account for',
    'account',
    'user',
    'is',
  ];

  /// Words that indicate a status question — stripped from the candidate
  /// ("is maria active" → "maria").
  static final _userFillerSuffix = RegExp(
    r'\s+(active|inactive|disabled|enabled|online|deleted|still here|'
    r'still employed|working today|a user|a staff|a staff member|'
    r'an admin|the owner|staff|admin|owner|member)\.?$',
    caseSensitive: false,
  );

  static const _genericUserTerms = {
    'user',
    'users',
    'account',
    'accounts',
    'staff',
    'admin',
    'admins',
    'owner',
    'owners',
    'everyone',
    'team',
    'members',
    'count',
    'list',
    'summary',
    'status',
    'management',
    'settings',
    'me',
    'my',
    'mine',
    'i',
    'all',
    'system',
    'the system',
  };

  static String? _extractUserCandidate(String query) {
    final q = query.toLowerCase().trim();
    for (final prefix in _userLookupPrefixes) {
      // Prefix must be followed by a space so 'user' can't match
      // 'username' or 'is' can't match 'issue'.
      if (!q.startsWith('$prefix ')) continue;
      var rest = q.substring(prefix.length).trim();
      rest = rest.replaceAll(RegExp(r'[?.!]+$'), '').trim();
      while (true) {
        final stripped = rest.replaceAll(_userFillerSuffix, '').trim();
        if (stripped == rest) break;
        rest = stripped;
      }
      rest = rest
          .replaceAll(RegExp(r'^(the|a|an|ang|yung|si|sa)\s+'), '')
          .trim();
      if (rest.isEmpty) return null;
      if (_genericUserTerms.contains(rest)) return null;
      return rest;
    }
    return null;
  }

  /// A full receipt number (`YYYYMMDD-NNNN`) mentioned anywhere in the
  /// query, or a sale/transaction/order keyword followed by digits.
  static final _saleReferencePattern = RegExp(
    r'(?:receipt|sale|transaction|order)\b\s*(?:#|number|num|no\.?|id)?'
    r'\s*[:\s-]*\d',
    caseSensitive: false,
  );

  /// Captures the numeric id after a sale/transaction/order keyword —
  /// "sale #42" → 42, "receipt: 7" → 7.
  static final _saleIdCapturePattern = RegExp(
    r'(?:receipt|sale|transaction|order)\b\s*(?:#|number|num|no\.?|id)?'
    r'\s*[:\s-]*(\d+)',
    caseSensitive: false,
  );
  static final _receiptNumberPattern = RegExp(r'\b\d{8}-\d{3,}\b');

  /// Words that identify a staff/user-account question for the owner —
  /// "my staff", "employees", "team members", "users", "who works here".
  static final _staffAccountPattern = RegExp(
    r'\b(staff|employees?|team(\s*members?)?|users?|accounts?)\b|'
    r'\bwho\s+works?\b',
    caseSensitive: false,
  );

  static const _latestSalePhrases = [
    'latest sale',
    'last sale',
    'most recent sale',
    'latest transaction',
    'last transaction',
    'most recent transaction',
    'latest order',
    'last order',
  ];

  bool _containsSaleReference(String q) {
    return _saleReferencePattern.hasMatch(q) ||
        _receiptNumberPattern.hasMatch(q) ||
        _matches(q, _latestSalePhrases);
  }

  /// True when the query asks about a payment-method split (GCash vs
  /// cash): the method keyword plus an amount/sales cue.
  bool _mentionsPaymentMethodSplit(String q) {
    final mentionsMethod =
        q.contains('gcash') || RegExp(r'\bcash\b').hasMatch(q);
    if (!mentionsMethod) return false;
    return _matches(q, [
      'sales',
      'sale',
      'payment',
      'payments',
      'breakdown',
      'vs',
      'versus',
      'total',
      'much',
      'many',
      'paid',
      'share',
      'split',
      'made',
      'collected',
      'received',
      'took in',
      'earnings',
    ]);
  }

  /// Resolves the products named in [q]: an explicit lookup candidate
  /// first, then a whole-word mention scan across active product names.
  List<Product> _resolveProductMentions(List<Product> products, String q) {
    final matches = <Product>[];
    final candidate = extractProductCandidate(q);
    if (candidate != null) {
      matches.addAll(
        products.where((p) => p.name.toLowerCase().trim() == candidate),
      );
      if (matches.isEmpty) {
        matches.addAll(products.where((p) {
          final name = p.name.toLowerCase().trim();
          return name.contains(candidate) || candidate.contains(name);
        }));
      }
    }
    if (matches.isEmpty) {
      for (final p in products) {
        if (p.name.trim().length < 3) continue;
        if (_nameMentioned(p.name, q)) {
          matches.add(p);
        }
      }
    }
    // Prefer the shortest (closest) names first when many match.
    matches.sort((a, b) => a.name.length.compareTo(b.name.length));
    return matches.take(6).toList();
  }

  /// Looks up the product(s) named in the query: real price, stock,
  /// category, and recent sales velocity. Never fabricates a match —
  /// when nothing resolves, the facts say so and list a sample of the
  /// catalog so the AI can redirect the user.
  Future<BusinessFacts> _gatherProductLookup(
    DetectedIntent d, {
    String? query,
  }) async {
    final q = (query ?? '').toLowerCase();
    final products = await _productRepository.getActiveProducts();
    final matches = _resolveProductMentions(products, q);

    final buf = StringBuffer();
    if (matches.isEmpty) {
      final candidate = extractProductCandidate(q);
      buf.writeln('--- PRODUCT LOOKUP ---');
      buf.writeln(
        'No active product matched ${candidate != null ? '"$candidate"' : 'the query'}.',
      );
      buf.writeln('Total active products: ${products.length}');
      if (products.isNotEmpty) {
        buf.writeln('Available products (sample):');
        for (final p in products.take(12)) {
          buf.writeln('  - ${p.name} (PHP ${_formatMoney(p.price)})');
        }
        if (products.length > 12) {
          buf.writeln('  ... and ${products.length - 12} more.');
        }
      }
      buf.writeln('--- END DATA ---');
      return BusinessFacts(
        context: buf.toString(),
        intent: d.intent,
        hasData: false,
      );
    }

    final categories = await _categoryRepository.getActiveCategories();
    final catNames = {for (final c in categories) c.id!: c.name};
    final velocity = await _saleItemRepository.getTopProducts(
      limit: 200,
      since: DateTime.now().subtract(const Duration(days: 30)),
    );
    final sold30 = {
      for (final t in velocity)
        t['product_id'] as int: t['total_quantity'] as int,
    };

    buf.writeln('--- PRODUCT LOOKUP RESULTS ---');
    for (final p in matches) {
      buf.writeln('  - ${p.name}: PHP ${_formatMoney(p.price)}; '
          'stock: ${p.stock} units (min: ${p.minStock}); '
          'category: ${catNames[p.categoryId] ?? 'Uncategorized'}; '
          'sold last 30 days: ${sold30[p.id] ?? 0} units'
          '${p.isLowStock ? '; LOW STOCK' : ''}');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  /// Looks up a specific sale by receipt number, internal id, or
  /// "latest/last sale". Staff are scoped to their own sales — the
  /// `user_id` filter is applied inside the repository query.
  Future<BusinessFacts> _gatherSaleLookup(
    DetectedIntent d, {
    UserRole? role,
    int? userId,
    String? query,
  }) async {
    final q = (query ?? '').toLowerCase();
    final scopedUserId = role == UserRole.staff ? userId : null;
    if (role == UserRole.staff && userId == null) return _noUserData(d);

    Sale? sale;
    final receiptNo = _receiptNumberPattern.firstMatch(q)?.group(0);
    if (receiptNo != null) {
      final results = await _saleRepository.getFilteredSales(
        search: receiptNo,
        userId: scopedUserId,
        limit: 20,
      );
      for (final s in results) {
        if (!s.isDeleted && s.receiptNumber == receiptNo) {
          sale = s;
          break;
        }
      }
    }

    // Fall back to a numeric sale id only when the query did NOT carry a
    // full receipt number — otherwise '20260908' would be misread as id.
    if (sale == null && receiptNo == null) {
      final idMatch = _saleIdCapturePattern.firstMatch(q);
      final id =
          idMatch == null ? null : int.tryParse(idMatch.group(1)!);
      if (id != null) {
        final found = await _saleRepository.getById(id);
        if (found != null &&
            !found.isDeleted &&
            (scopedUserId == null || found.userId == scopedUserId)) {
          sale = found;
        }
      }
    }

    if (sale == null && _matches(q, _latestSalePhrases)) {
      final recent = scopedUserId != null
          ? await _saleRepository.getByUserId(scopedUserId, limit: 1)
          : await _saleRepository.getAllActive(limit: 1);
      for (final s in recent) {
        if (!s.isDeleted) {
          sale = s;
          break;
        }
      }
    }

    if (sale == null) {
      return BusinessFacts(
        context: '--- SALE LOOKUP ---\n'
            'No matching sale was found for this query.'
            '${role == UserRole.staff ? ' (You can only look up your own sales.)' : ''}\n'
            '--- END DATA ---',
        intent: d.intent,
        hasData: false,
      );
    }

    final items = await _saleItemRepository.getBySaleId(sale.id!);
    String? recordedBy;
    if (role != UserRole.staff) {
      final u = await _userRepository.getById(sale.userId);
      recordedBy = u?.fullName;
    }

    final buf = StringBuffer();
    buf.writeln('--- SALE LOOKUP RESULT ---');
    buf.writeln('Receipt number: ${sale.receiptNumber ?? '(none assigned)'}');
    buf.writeln('Sale ID: ${sale.id}');
    buf.writeln('Date: ${_formatDateTime(sale.createdAt)}');
    buf.writeln('Total: PHP ${_formatMoney(sale.totalAmount)}');
    buf.writeln('Payment method: ${sale.paymentMethod}');
    buf.writeln('Payment status: ${sale.paymentStatus}');
    if (sale.paymentMethod == 'Cash') {
      buf.writeln('Cash received: PHP ${_formatMoney(sale.cashReceived)}');
      buf.writeln('Change: PHP ${_formatMoney(sale.change)}');
    }
    if (sale.referenceNumber != null && sale.referenceNumber!.isNotEmpty) {
      buf.writeln('GCash reference: ${sale.referenceNumber}');
    }
    if (sale.customerName != null && sale.customerName!.isNotEmpty) {
      buf.writeln('Customer: ${sale.customerName}');
    }
    if (recordedBy != null) {
      buf.writeln('Recorded by: $recordedBy');
    }
    if (sale.isPending) {
      buf.writeln('NOTE: This sale is pending GCash verification.');
    }
    if (sale.isCancelled) {
      buf.writeln('NOTE: This sale was ${sale.paymentStatus}.');
    }
    buf.writeln('');
    if (items.isEmpty) {
      buf.writeln('Items: none recorded.');
    } else {
      buf.writeln('Items (${items.length}):');
      for (final item in items) {
        buf.writeln('  - ${item.productName ?? 'Product #${item.productId}'}: '
            '${item.quantity} × PHP ${_formatMoney(item.unitPrice)} = '
            'PHP ${_formatMoney(item.totalPrice)}');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  /// Cash vs GCash (and any other method) totals for the requested
  /// period. Staff results are scoped to their own sales.
  Future<BusinessFacts> _gatherPaymentBreakdown(
    DetectedIntent d, {
    UserRole? role,
    int? userId,
  }) async {
    final scopedUserId = role == UserRole.staff ? userId : null;
    if (role == UserRole.staff && userId == null) return _noUserData(d);

    final now = DateTime.now();
    final today = startOfDay(now);
    final start = d.startDate ?? today;
    final end = d.endDate ?? today.add(const Duration(days: 1));

    final breakdown = await _saleRepository.getPaymentBreakdown(
      start,
      end,
      userId: scopedUserId,
    );
    final grandTotal =
        breakdown.fold<double>(0, (sum, p) => sum + p.total);
    final totalCount = breakdown.fold<int>(0, (sum, p) => sum + p.count);

    final buf = StringBuffer();
    buf.writeln('--- PAYMENT METHOD BREAKDOWN '
        '(${d.periodDescription ?? 'period'}'
        '${scopedUserId != null ? ', your sales only' : ''}) ---');
    buf.writeln(
        'Period: ${_formatDate(start)} to ${_formatDate(end.subtract(const Duration(days: 1)))}');
    if (breakdown.isEmpty || grandTotal <= 0) {
      buf.writeln('No confirmed sales in this period.');
    } else {
      for (final p in breakdown) {
        buf.writeln('  - ${p.method}: PHP ${_formatMoney(p.total)} '
            '(${p.count} transactions, '
            '${p.percentageOf(grandTotal).toStringAsFixed(1)}% of total)');
      }
      buf.writeln('  Total: PHP ${_formatMoney(grandTotal)} '
          '($totalCount transactions)');
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: breakdown.isNotEmpty,
    );
  }

  /// Looks up a specific user account by name or username (Admin and
  /// Owner — Staff cannot see other users' accounts). Never exposes
  /// credentials — only account state fields.
  Future<BusinessFacts> _gatherUserLookup(
    DetectedIntent d, {
    String? query,
  }) async {
    final q = (query ?? '').toLowerCase();
    final candidate = _extractUserCandidate(q);
    final users = await _userRepository.getAllActive();

    final matches = <User>[];
    if (candidate != null && candidate.isNotEmpty) {
      final c = candidate.toLowerCase();
      matches.addAll(users.where(
        (u) =>
            u.username.toLowerCase() == c || u.fullName.toLowerCase() == c,
      ));
      if (matches.isEmpty) {
        matches.addAll(users.where((u) {
          final full = u.fullName.toLowerCase();
          final uname = u.username.toLowerCase();
          return full.contains(c) || uname.contains(c);
        }));
      }
    }
    if (matches.isEmpty) {
      // Mention scan: the query may name a user without a lookup
      // prefix — or with a typo ("who is maira" still finds Maria).
      for (final u in users) {
        if (_nameMentioned(u.fullName, q) ||
            _nameMentioned(u.username, q)) {
          matches.add(u);
        }
      }
    }

    final buf = StringBuffer();
    if (matches.isEmpty) {
      buf.writeln('--- USER LOOKUP ---');
      buf.writeln(
        'No user account matched ${candidate != null ? '"$candidate"' : 'the query'}.',
      );
      buf.writeln('Total user accounts (not deleted): ${users.length}');
      if (users.isNotEmpty) {
        buf.writeln('User accounts (sample):');
        for (final u in users.take(10)) {
          buf.writeln(
              '  - ${u.fullName} (@${u.username}, ${u.role.displayName})');
        }
      }
      buf.writeln('--- END DATA ---');
      return BusinessFacts(
        context: buf.toString(),
        intent: d.intent,
        hasData: false,
      );
    }

    buf.writeln('--- USER LOOKUP RESULTS ---');
    for (final u in matches.take(5)) {
      buf.writeln('  - ${u.fullName} (@${u.username})');
      buf.writeln('    Role: ${u.role.displayName}');
      buf.writeln('    Status: ${u.isActive ? 'active' : 'inactive'}');
      buf.writeln('    Last login: '
          '${u.lastLogin != null ? _formatDateTime(u.lastLogin!) : 'never'}');
      buf.writeln('    Account created: ${_formatDate(u.createdAt)}');
      if (u.mustChangePassword) {
        buf.writeln('    Password change required on next login: yes');
      }
    }
    buf.writeln('--- END DATA ---');

    return BusinessFacts(
      context: buf.toString(),
      intent: d.intent,
      hasData: true,
    );
  }

  /// When a general-intent query names a product, return the real product
  /// facts instead of the thin generic context. Returns null when no
  /// product matches.
  Future<BusinessFacts?> _tryProductLookupFacts(
    DetectedIntent d,
    String q,
  ) async {
    final products = await _productRepository.getActiveProducts();
    if (_resolveProductMentions(products, q).isEmpty) return null;
    return _gatherProductLookup(d, query: q);
  }

  /// When a general-intent query references a specific sale/receipt,
  /// return the real sale facts. Returns null when the query carries no
  /// sale reference at all (a "not found" lookup result IS returned).
  Future<BusinessFacts?> _trySaleLookupFacts(
    DetectedIntent d,
    String q, {
    UserRole? role,
    int? userId,
  }) async {
    if (!_containsSaleReference(q)) return null;
    return _gatherSaleLookup(d, role: role, userId: userId, query: q);
  }

  /// Counterpart for user-account mentions in a general query — runs
  /// for the roles allowed to see user accounts (Admin and Owner).
  Future<BusinessFacts?> _tryUserLookupFacts(
    DetectedIntent d,
    String q,
  ) async {
    final users = await _userRepository.getAllActive();
    var found = false;
    for (final u in users) {
      if (_nameMentioned(u.fullName, q) || _nameMentioned(u.username, q)) {
        found = true;
        break;
      }
    }
    if (!found) return null;
    return _gatherUserLookup(d, query: q);
  }

  Future<BusinessFacts> _gatherGeneralContext(
    DetectedIntent d, {
    UserRole? role,
    int? userId,
    String? query,
  }) async {
    // When an unmatched query names a specific entity the role can see,
    // answer it with real data rather than thin generic context. This is
    // what makes phrasing like "coke price" or "anong laman ng
    // 20260908-0001" reach the database even without a detected intent.
    final q = (query ?? '').toLowerCase();
    if (q.isNotEmpty) {
      if (role == UserRole.admin) {
        final userFacts = await _tryUserLookupFacts(d, q);
        if (userFacts != null) return userFacts;
      } else {
        final productFacts = await _tryProductLookupFacts(d, q);
        if (productFacts != null) return productFacts;
        final saleFacts =
            await _trySaleLookupFacts(d, q, role: role, userId: userId);
        if (saleFacts != null) return saleFacts;
        // The owner may also name a staff member/user account —
        // resolve it against the real users table.
        if (role == UserRole.owner) {
          final userFacts = await _tryUserLookupFacts(d, q);
          if (userFacts != null) return userFacts;
        }
      }
    }

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

      final users = await _userRepository.getAllActive();

      buf.writeln('--- GENERAL BUSINESS CONTEXT ---');
      buf.writeln('Today\'s sales: PHP ${_formatMoney(todayTotal)} '
          '(${todayActive.length} transactions)');
      buf.writeln('Active products: ${products.length}');
      buf.writeln('Low stock items: ${lowStock.length}');
      buf.writeln('');
      buf.writeln('Team accounts (${users.length}):');
      for (final u in users.take(20)) {
        buf.writeln('  - ${u.fullName} (${u.role.displayName})'
            '${u.isActive ? '' : ' — inactive'}');
      }
      buf.writeln('');
      buf.writeln('NOTE: This is general context only. For specific '
          'analysis, ask about sales, products, inventory, staff, '
          'users, activity, backups, or request a business summary.');
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

      // Surface staff visibility when the team has members.
      final users = await _userRepository.getAllActive();
      if (users.any((u) => u.role == UserRole.staff)) {
        suggestions.add('Who are my staff?');
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

  /// Generates follow-up question suggestions that adapt to the
  /// conversation. Re-runs [detectIntent] on the user's latest query and
  /// maps the detected intent to a curated set of natural next questions
  /// for the user's role.
  ///
  /// This is a pure local computation — it does not call the AI service
  /// and does not consume the daily query quota.
  ///
  /// [exclude] receives the questions the user already asked (raw text);
  /// matching candidates are skipped so the chips keep evolving instead of
  /// repeating the conversation. Falls back to a role-level pool when the
  /// intent-specific set is exhausted. Returns at most [maxSuggestions].
  List<String> generateFollowUpSuggestions(
    String userQuery, {
    UserRole? role,
    Set<String> exclude = const {},
    int maxSuggestions = 3,
  }) {
    final effectiveRole = role ?? _sessionManager.currentUser?.role;
    final detected = detectIntent(userQuery, role: effectiveRole);

    final asked = <String>{
      _normalizeFollowUpKey(userQuery),
      for (final q in exclude) _normalizeFollowUpKey(q),
    };

    final pools = switch (effectiveRole) {
      UserRole.admin => _adminFollowUpSuggestions,
      UserRole.staff => _staffFollowUpSuggestions,
      _ => _ownerFollowUpSuggestions,
    };
    final fallback = switch (effectiveRole) {
      UserRole.admin => _adminFallbackFollowUps,
      UserRole.staff => _staffFallbackFollowUps,
      _ => _ownerFallbackFollowUps,
    };

    final result = <String>[];
    void addCandidates(Iterable<String> candidates) {
      for (final candidate in candidates) {
        if (result.length >= maxSuggestions) return;
        if (asked.contains(_normalizeFollowUpKey(candidate))) continue;
        if (result.contains(candidate)) continue;
        result.add(candidate);
      }
    }

    addCandidates(pools[detected.intent] ?? const []);
    if (result.length < maxSuggestions) addCandidates(fallback);
    return result;
  }

  static String _normalizeFollowUpKey(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[?.!]+$'), '');

  // ── Follow-up suggestion pools ───────────────────────────────────────
  //
  // Every candidate is phrased so [detectIntent] resolves it to a real,
  // data-backed intent — tapping a chip never produces a dead-end query.
  // Pools are role-scoped so Staff is never offered business-wide or
  // administrative questions.

  static const Map<BusinessIntent, List<String>> _ownerFollowUpSuggestions = {
    BusinessIntent.todaySales: [
      'How do my sales compare to yesterday?',
      'What products are selling the most?',
      'Which products are low in stock?',
    ],
    BusinessIntent.yesterdaySales: [
      'How are my sales today?',
      'What products are selling the most?',
      'What should I restock soon?',
    ],
    BusinessIntent.dateRangeSales: [
      'Compare my sales to yesterday.',
      'What products are selling the most?',
      'Give me a business summary.',
    ],
    BusinessIntent.weeklySales: [
      'Compare my sales to last week.',
      'What products are selling the most?',
      'Which products are low in stock?',
    ],
    BusinessIntent.monthlySales: [
      'How are my sales this week?',
      'What products are selling the most?',
      'Give me a business summary.',
    ],
    BusinessIntent.salesComparison: [
      'What products are selling the most?',
      'Why did sales decrease this week?',
      'Which products are low in stock?',
    ],
    BusinessIntent.topProducts: [
      'Which products are low in stock?',
      'What should I restock soon?',
      'How are my sales today?',
    ],
    BusinessIntent.lowSellingProducts: [
      'What products are selling the most?',
      'What should I restock soon?',
      'What is my inventory status?',
    ],
    BusinessIntent.productPerformance: [
      'Which products are low selling?',
      'Which products are low in stock?',
      'How are my sales today?',
    ],
    BusinessIntent.lowStock: [
      'What should I restock soon?',
      'What products are selling the most?',
      'How are my sales today?',
    ],
    BusinessIntent.restockRecommendation: [
      'Which products are low in stock?',
      'What products are selling the most?',
      'Give me a business summary.',
    ],
    BusinessIntent.categoryPerformance: [
      'What products are selling the most?',
      'How are my sales this week?',
      'Which products are low in stock?',
    ],
    BusinessIntent.busiestPeriod: [
      'How are my sales this week?',
      'What products are selling the most?',
      'Give me a business summary.',
    ],
    BusinessIntent.inventoryStatus: [
      'What should I restock soon?',
      'Which products are low in stock?',
      'What products are selling the most?',
    ],
    BusinessIntent.trendAnalysis: [
      'How did my sales change this week?',
      'What products are selling the most?',
      'What should I focus on tomorrow?',
    ],
    BusinessIntent.businessSummary: [
      'How are my sales today?',
      'What products are selling the most?',
      'Which products are low in stock?',
      'What should I restock soon?',
    ],
    BusinessIntent.recentSales: [
      'How are my sales today?',
      'What was my latest sale?',
      'How much was paid via GCash today?',
    ],
    BusinessIntent.productLookup: [
      'Which products are low in stock?',
      'What products are selling the most?',
      'What should I restock soon?',
    ],
    BusinessIntent.saleLookup: [
      'Show recent sales.',
      'How much was paid via GCash today?',
      'How are my sales today?',
    ],
    BusinessIntent.paymentBreakdown: [
      'How are my sales today?',
      'Show recent sales.',
      'What was my latest sale?',
    ],
    BusinessIntent.staffSales: [
      'Who are my staff?',
      'How are my sales today?',
      'What products are selling the most?',
    ],
    BusinessIntent.userStatusSummary: [
      'Which staff sold the most today?',
      'How many users do I have?',
      'Show recent sales.',
    ],
    BusinessIntent.activeUserSummary: [
      'Who are my staff?',
      'Which staff sold the most today?',
      'Give me a business summary.',
    ],
    BusinessIntent.userLookup: [
      'Who are my staff?',
      'Which staff sold the most today?',
      'Show recent sales.',
    ],
    BusinessIntent.systemActivitySummary: [
      'Show recent activity.',
      'Who are my staff?',
      'Give me a business summary.',
    ],
    BusinessIntent.recentActivity: [
      'Summarize today\'s activity.',
      'Who are my staff?',
      'How are my sales today?',
    ],
    BusinessIntent.backupSummary: [
      'Show recent activity.',
      'Give me a business summary.',
      'How are my sales today?',
    ],
    BusinessIntent.exportSummary: [
      'When was the latest backup?',
      'Give me a business summary.',
      'How are my sales today?',
    ],
    BusinessIntent.systemStatusSummary: [
      'How many users do I have?',
      'When was the latest backup?',
      'Give me a business summary.',
    ],
  };

  static const List<String> _ownerFallbackFollowUps = [
    'How are my sales today?',
    'What products are selling the most?',
    'Which products are low in stock?',
    'What should I restock soon?',
    'Give me a business summary.',
  ];

  static const Map<BusinessIntent, List<String>> _adminFollowUpSuggestions = {
    BusinessIntent.activeUserSummary: [
      'Show recent system activity.',
      'When was the latest backup?',
      'Give me a system summary.',
    ],
    BusinessIntent.userStatusSummary: [
      'Show recent system activity.',
      'When was the latest backup?',
      'Give me a system summary.',
    ],
    BusinessIntent.systemActivitySummary: [
      'How many active users do we have?',
      'When was the latest backup?',
      'What was exported recently?',
    ],
    BusinessIntent.recentActivity: [
      'How many active users do we have?',
      'When was the latest backup?',
      'What was exported recently?',
    ],
    BusinessIntent.backupSummary: [
      'Show recent system activity.',
      'Give me a system summary.',
      'How many active users do we have?',
    ],
    BusinessIntent.exportSummary: [
      'Show recent system activity.',
      'When was the latest backup?',
      'Give me a system summary.',
    ],
    BusinessIntent.systemStatusSummary: [
      'How many active users do we have?',
      'Show recent system activity.',
      'When was the latest backup?',
    ],
    BusinessIntent.adminSummary: [
      'How many active users do we have?',
      'Show recent system activity.',
      'When was the latest backup?',
    ],
    BusinessIntent.userLookup: [
      'How many active users do we have?',
      'Show recent system activity.',
      'Give me a system summary.',
    ],
  };

  static const List<String> _adminFallbackFollowUps = [
    'How many active users do we have?',
    'Show recent system activity.',
    'When was the latest backup?',
    'Give me a system summary.',
  ];

  static const Map<BusinessIntent, List<String>> _staffFollowUpSuggestions = {
    BusinessIntent.myTodaySales: [
      'Which products sell best in my transactions?',
      'What products are low in stock?',
      'Show my recent sales.',
    ],
    BusinessIntent.myDateRangeSales: [
      'How much did I sell today?',
      'Which products sell best in my transactions?',
      'What products are low in stock?',
    ],
    BusinessIntent.myRecentSales: [
      'How much did I sell today?',
      'Which products sell best in my transactions?',
      'Give me a summary of my work today.',
    ],
    BusinessIntent.myTopSoldProducts: [
      'What products are low in stock?',
      'How much did I sell today?',
      'Show my recent sales.',
    ],
    BusinessIntent.lowStock: [
      'Show products.',
      'Which products sell best in my transactions?',
      'How much did I sell today?',
    ],
    BusinessIntent.productInformation: [
      'What products are low in stock?',
      'Which products sell best in my transactions?',
      'Show my recent sales.',
    ],
    BusinessIntent.categoryInformation: [
      'What products are low in stock?',
      'Which products sell best in my transactions?',
      'Show my recent sales.',
    ],
    BusinessIntent.myActivitySummary: [
      'How much did I sell today?',
      'Show my recent sales.',
      'What products are low in stock?',
    ],
    BusinessIntent.myWorkSummary: [
      'How much did I sell today?',
      'Show my recent sales.',
      'What products are low in stock?',
    ],
    BusinessIntent.productLookup: [
      'What products are low in stock?',
      'Show my recent sales.',
      'How much did I sell today?',
    ],
    BusinessIntent.saleLookup: [
      'Show my recent sales.',
      'How much did I sell today?',
      'Give me a summary of my work today.',
    ],
    BusinessIntent.paymentBreakdown: [
      'How much did I sell today?',
      'Show my recent sales.',
      'What products are low in stock?',
    ],
  };

  static const List<String> _staffFallbackFollowUps = [
    'How much did I sell today?',
    'Show my recent sales.',
    'What products are low in stock?',
    'Which products sell best in my transactions?',
  ];

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

    // Specific user account lookup — "who is maria", "is john active".
    // Runs after the aggregate user blocks so 'how many users' etc. keep
    // resolving to summaries.
    if (_extractUserCandidate(q) != null) {
      return DetectedIntent(
        intent: BusinessIntent.userLookup,
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
    // Specific sale/receipt lookup — scoped to the staff member's own
    // sales at the SQL level inside _gatherSaleLookup.
    if (_containsSaleReference(q)) {
      return DetectedIntent(
        intent: BusinessIntent.saleLookup,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Payment-method split for own sales ("how much GCash did I take
    // today"). Checked before the generic "my sales" block.
    if (_mentionsPaymentMethodSplit(q)) {
      return DetectedIntent(
        intent: BusinessIntent.paymentBreakdown,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

    // Specific product lookup — "price of coke", "stock of lucky me".
    if (extractProductCandidate(q) != null) {
      return DetectedIntent(
        intent: BusinessIntent.productLookup,
        startDate: startDate,
        endDate: endDate,
        periodDescription: periodDesc,
      );
    }

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
    final topProducts = await _saleItemRepository.getTopProducts(
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
    final myTopProducts = await _saleItemRepository.getTopProducts(
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

  // ── Audit signals (deterministic anomaly detection) ────────────────
  //
  // Computed in Dart from SQL-aggregated daily totals — no ML model, no
  // arbitrary SQL. Signals are descriptive statistics over the last
  // 28 days so the AI can cite real deviations instead of speculating.

  /// Baseline window for audit computations (complete days before today).
  static const int _auditBaselineDays = 28;

  /// Minimum number of baseline days with data before signals are trusted.
  static const int _auditMinBaselineDays = 7;

  /// Builds a compact AUDIT SIGNALS block for the AI context.
  ///
  /// Owner gets business-wide signals; Staff gets signals scoped to
  /// `sales.user_id = userId` at the SQL level; Admin and missing users
  /// get none.
  Future<String> _buildAuditSignals({UserRole? role, int? userId}) async {
    if (role == UserRole.admin) return '';
    final scopedUserId = role == UserRole.staff ? userId : null;
    if (role == UserRole.staff && userId == null) return '';

    final now = DateTime.now();
    final today = startOfDay(now);
    final baselineStart = today.subtract(
      const Duration(days: _auditBaselineDays),
    );

    // Daily totals (SQL-aggregated, confirmed sales only).
    final points = await _saleRepository.getSalesTrend(
      baselineStart,
      today.add(const Duration(days: 1)),
      groupBy: ReportGroupBy.day,
      userId: scopedUserId,
    );

    final baseline = points
        .where((p) => !startOfDay(p.date).isAtSameMomentAs(today))
        .toList();
    final todayPoint = points
        .where((p) => startOfDay(p.date).isAtSameMomentAs(today))
        .fold<DailySalesPoint?>(null, (a, b) => a == null
            ? b
            : DailySalesPoint(
                date: b.date,
                total: a.total + b.total,
                count: a.count + b.count));
    final todayTotal = todayPoint?.total ?? 0.0;

    if (baseline.length < _auditMinBaselineDays) {
      return '--- AUDIT SIGNALS ---\n'
          'Not enough history (${baseline.length} days with sales in the '
          'last $_auditBaselineDays days) to compute a reliable baseline. '
          'Treat today\'s numbers as-is, without anomaly flags.\n'
          '--- END AUDIT ---';
    }

    // Baseline statistics over days that had sales.
    final totals = baseline.map((p) => p.total).toList();
    final mean = totals.reduce((a, b) => a + b) / totals.length;
    final variance = totals
            .map((t) => (t - mean) * (t - mean))
            .reduce((a, b) => a + b) /
        totals.length;
    final stddev = sqrt(variance);
    final zScore = stddev > 0 ? (todayTotal - mean) / stddev : 0.0;

    // Same-weekday baseline (e.g. the last ~4 Fridays vs today).
    final sameWeekday = baseline
        .where((p) => p.date.weekday == now.weekday)
        .toList();
    final sameWeekdayAvg = sameWeekday.isEmpty
        ? null
        : sameWeekday.map((p) => p.total).reduce((a, b) => a + b) /
            sameWeekday.length;

    // Payment-method mix shift (share of revenue, today vs baseline).
    final todayBreakdown = await _saleRepository.getPaymentBreakdown(
      today,
      today.add(const Duration(days: 1)),
      userId: scopedUserId,
    );
    final baselineBreakdown = await _saleRepository.getPaymentBreakdown(
      baselineStart,
      today,
      userId: scopedUserId,
    );
    String? mixSignal;
    if (todayBreakdown.isNotEmpty && baselineBreakdown.isNotEmpty) {
      final todayGrand =
          todayBreakdown.fold<double>(0, (s, p) => s + p.total);
      final baseGrand =
          baselineBreakdown.fold<double>(0, (s, p) => s + p.total);
      if (todayGrand > 0 && baseGrand > 0) {
        final topToday = todayBreakdown.first;
        final baseMatch = baselineBreakdown
            .where((p) => p.method == topToday.method)
            .firstOrNull;
        final todayShare = topToday.percentageOf(todayGrand);
        final baseShare =
            baseMatch?.percentageOf(baseGrand) ?? 0.0;
        final shift = todayShare - baseShare;
        if (shift.abs() >= 10) {
          mixSignal = 'Payment mix: ${topToday.method} is '
              '${todayShare.toStringAsFixed(0)}% of today\'s sales vs '
              '${baseShare.toStringAsFixed(0)}% over the baseline '
              '(shift of ${shift >= 0 ? '+' : ''}'
              '${shift.toStringAsFixed(0)} points).';
        }
      }
    }

    String verdict;
    if (zScore.abs() < 1.75) {
      verdict = 'within the normal range';
    } else if (zScore.abs() < 2.5) {
      verdict = zScore > 0
          ? 'notably above normal'
          : 'notably below normal';
    } else {
      verdict = zScore > 0
          ? 'unusually high (strong positive anomaly)'
          : 'unusually low (strong negative anomaly)';
    }

    final buf = StringBuffer();
    buf.writeln('--- AUDIT SIGNALS '
        '(computed from the last $_auditBaselineDays days) ---');
    buf.writeln('Baseline: PHP ${_formatMoney(mean)} average per sales day '
        'across ${baseline.length} days (std dev PHP '
        '${_formatMoney(stddev)}).');
    buf.writeln('Today vs baseline: ${mean > 0 ? (((todayTotal - mean) / mean) * 100).toStringAsFixed(1) : '0.0'}% '
        '(z-score ${zScore.toStringAsFixed(2)}) — $verdict.');
    if (sameWeekdayAvg != null && sameWeekdayAvg > 0) {
      final diff = ((todayTotal - sameWeekdayAvg) / sameWeekdayAvg) * 100;
      buf.writeln('Same-weekday check: recent ${_weekdayName(now.weekday)}s '
          'averaged PHP ${_formatMoney(sameWeekdayAvg)}; today is '
          '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}% vs that.');
    }
    if (mixSignal != null) buf.writeln(mixSignal);
    buf.writeln('These signals are computed from recorded sales and are '
        'flags to investigate, not proven causes.');
    buf.writeln('--- END AUDIT ---');
    return buf.toString();
  }

  static String _weekdayName(int weekday) {
    const names = [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday',
    ];
    return names[weekday.clamp(1, 7)];
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

  /// Intent-relevant vocabulary used for typo correction. Any query
  /// token within one edit (substitution, insertion, deletion, or
  /// adjacent transposition) of a word here is snapped to it, so
  /// "saels", "staf", and "gcahs" still detect correctly.
  static const _intentVocabulary = {
    'how', 'who', 'whos', 'what', 'when', 'where', 'which',
    'show', 'list', 'count', 'many', 'much',
    'sales', 'sale', 'sold', 'selling', 'seller',
    'staff', 'employee', 'employees', 'team', 'members',
    'user', 'users', 'account', 'accounts', 'admin', 'owner',
    'product', 'products', 'category', 'categories',
    'stock', 'stocks', 'inventory', 'restock',
    'receipt', 'transaction', 'transactions', 'order',
    'gcash', 'cash', 'payment', 'paid',
    'price', 'cost',
    'today', 'yesterday', 'tomorrow', 'week', 'month',
    'daily', 'weekly', 'monthly',
    'total', 'amount', 'income', 'revenue', 'earning', 'earnings',
    'profit', 'activity', 'backup', 'export', 'system', 'status',
    'active', 'inactive', 'recent', 'latest', 'best', 'worst',
    'most', 'least', 'highest', 'lowest', 'summary', 'report',
    'overview', 'performance', 'trend', 'customer', 'customers',
  };

  /// Explicit corrections for common misspellings, keyboard slips, and
  /// Taglish phrasing — covers cases a one-edit fuzzy match cannot.
  static const _queryCorrections = {
    'usr': 'user', 'usrs': 'users', 'uers': 'users',
    'staf': 'staff', 'stafs': 'staff', 'staffs': 'staff',
    'employe': 'employee', 'employes': 'employees',
    'emplyee': 'employee', 'employye': 'employee',
    'prodct': 'product', 'prodcts': 'products', 'prodcut': 'product',
    'prodcuts': 'products', 'porduct': 'product', 'porducts': 'products',
    'stok': 'stock', 'stcok': 'stock', 'stck': 'stock', 'stoks': 'stock',
    'invntory': 'inventory', 'inventroy': 'inventory',
    'inventry': 'inventory', 'inventori': 'inventory',
    'reciept': 'receipt', 'recipt': 'receipt', 'resept': 'receipt',
    'transation': 'transaction', 'transction': 'transaction',
    'transations': 'transactions', 'transacions': 'transactions',
    'trnsaction': 'transaction', 'trnsactions': 'transactions',
    'gcas': 'gcash', 'gcahs': 'gcash', 'gcashh': 'gcash',
    'gcaash': 'gcash', 'gcashs': 'gcash',
    'yestrday': 'yesterday', 'yesteday': 'yesterday',
    'ystarday': 'yesterday', 'yterday': 'yesterday',
    'tomorow': 'tomorrow', 'tommorrow': 'tomorrow', 'tomorrw': 'tomorrow',
    'bakcup': 'backup', 'bakup': 'backup', 'backp': 'backup',
    'bckup': 'backup', 'backups': 'backup',
    'activty': 'activity', 'activiy': 'activity', 'actvity': 'activity',
    'activites': 'activity', 'activitie': 'activity',
    'catgory': 'category', 'categry': 'category', 'categoy': 'category',
    'categores': 'categories', 'catgories': 'categories',
    'custmer': 'customer', 'costumer': 'customer', 'cstomer': 'customer',
    'custmers': 'customers', 'costumers': 'customers',
    'prce': 'price', 'pice': 'price', 'prize': 'price', 'rpice': 'price',
    'paymnt': 'payment', 'paymnet': 'payment', 'pyament': 'payment',
    'paymet': 'payment',
    'amout': 'amount', 'amont': 'amount', 'ammount': 'amount',
    'totl': 'total', 'totla': 'total', 'ttal': 'total',
    'mont': 'month', 'mnth': 'month', 'motnh': 'month',
    'wek': 'week', 'weel': 'week', 'weekk': 'week',
    'restok': 'restock', 'restck': 'restock', 'resock': 'restock',
    'perfomance': 'performance', 'performace': 'performance',
    'perfomrmance': 'performance',
    'recnt': 'recent', 'recetn': 'recent', 'lates': 'latest',
    'sumary': 'summary', 'summay': 'summary', 'sumamry': 'summary',
    'hwo': 'how', 'woh': 'who', 'wht': 'what', 'whats': 'what',
    'whtas': 'what', 'wich': 'which', 'whic': 'which', 'shw': 'show',
    'sohw': 'show', 'lst': 'list', 'lsit': 'list', 'ilst': 'list',
    'manny': 'many', 'mny': 'many', 'mcuh': 'much', 'mch': 'much',
    'teh': 'the', 'adn': 'and', 'nad': 'and', 'fro': 'for', 'fo': 'for',
    // Taglish phrasing users naturally type.
    'magkno': 'how much', 'magkano': 'how much', 'mkano': 'how much',
    'hm': 'how much', 'howmuch': 'how much',
    'ilan': 'how many', 'ilang': 'how many', 'pilan': 'how many',
    'presyo': 'price', 'presyu': 'price',
    'kita': 'sales', 'benta': 'sales', 'tinda': 'products',
    'sino': 'who', 'ano': 'what', 'anong': 'what',
  };

  /// Normalizes the raw query for intent detection: lowercase,
  /// punctuation stripped (receipt numbers and `#` references kept),
  /// whitespace collapsed, and misspelled tokens snapped to the
  /// [_intentVocabulary]. Entity extraction still runs on the raw
  /// query, so a correction can never corrupt a product or user name.
  String _normalizeQuery(String query) {
    var q = query.toLowerCase().trim();
    q = q.replaceAll(RegExp('[!?.,;:\'"()]'), ' ');
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) return q;
    return q.split(' ').map(_correctToken).join(' ');
  }

  String _correctToken(String token) {
    final direct = _queryCorrections[token];
    if (direct != null) return direct;
    if (token.length < 4) return token;
    if (_intentVocabulary.contains(token)) return token;
    if (double.tryParse(token) != null) return token;
    if (_receiptNumberPattern.hasMatch(token)) return token;
    for (final word in _intentVocabulary) {
      if (word.length < 4) continue;
      if ((token.length - word.length).abs() > 1) continue;
      if (_isOneEditAway(token, word)) return word;
    }
    return token;
  }

  /// True when [a] is one substitution, insertion, deletion, or
  /// adjacent transposition away from [b] — e.g. "saels" → "sales",
  /// "staf" → "staff", "gcahs" → "gcash".
  static bool _isOneEditAway(String a, String b) {
    var x = a;
    var y = b;
    if (x.length > y.length) {
      final t = x;
      x = y;
      y = t;
    }
    final lx = x.length;
    final ly = y.length;
    if (ly - lx > 1) return false;
    if (lx == ly) {
      var first = -1;
      var second = -1;
      var diffs = 0;
      for (var i = 0; i < lx; i++) {
        if (x[i] != y[i]) {
          diffs++;
          if (first < 0) {
            first = i;
          } else {
            second = i;
          }
        }
      }
      if (diffs == 1) return true;
      return diffs == 2 &&
          second == first + 1 &&
          x[first] == y[second] &&
          x[second] == y[first];
    }
    // x is one character shorter — allow a single insertion in y.
    var i = 0;
    var j = 0;
    var skipped = false;
    while (i < lx && j < ly) {
      if (x[i] == y[j]) {
        i++;
        j++;
      } else {
        if (skipped) return false;
        skipped = true;
        j++;
      }
    }
    return true;
  }

  /// True when [name] (a user's full name, username, or a product
  /// name) is mentioned in [q] — an exact word-boundary match first,
  /// then a one-edit fuzzy match per token so "maira" still finds
  /// "Maria" and "cokke" still finds "Coke". Intent vocabulary words
  /// are excluded from the fuzzy pass so keywords can't false-match
  /// an entity.
  bool _nameMentioned(String name, String q) {
    final lowered = name.toLowerCase().trim();
    if (lowered.length >= 3 &&
        RegExp('\\b${RegExp.escape(lowered)}\\b').hasMatch(q)) {
      return true;
    }
    final nameTokens =
        lowered.split(RegExp(r'\s+')).where((t) => t.length >= 4);
    if (nameTokens.isEmpty) return false;
    final qTokens = q
        .split(' ')
        .map((t) => t.replaceAll(RegExp('[^a-z0-9]'), ''))
        .where((t) => t.length >= 4 && !_intentVocabulary.contains(t));
    for (final nt in nameTokens) {
      if (qTokens.any((qt) => _isOneEditAway(qt, nt))) return true;
    }
    return false;
  }

  bool _matches(String query, List<String> patterns) {
    // The normalized query has no apostrophes, so strip them from the
    // patterns too — "today's activity" still matches "todays ...".
    return patterns.any((p) => query.contains(p.replaceAll("'", '')));
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
