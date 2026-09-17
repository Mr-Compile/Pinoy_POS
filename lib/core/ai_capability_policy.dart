import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';

/// Centralized AI capability policy — the SINGLE SOURCE OF TRUTH for
/// which AI analytical intents each role is allowed to use.
///
/// This policy is enforced at THREE layers:
/// 1. **UI** — suggested questions and headers are role-specific.
/// 2. **Service** — [AIAdvisorService] checks the policy before gathering
///    facts and building the system prompt.
/// 3. **Database** — [BusinessIntelligenceService] only executes queries
///    for intents the current role is authorized to access. Staff queries
///    are additionally filtered by `currentUserId` at the SQL level.
///
/// The AI NEVER bypasses this policy. The user's message cannot override
/// the role determined from the authenticated session.
class AICapabilityPolicy {
  AICapabilityPolicy._();

  /// Returns the set of [BusinessIntent]s the given [role] is authorized
  /// to use through the AI Advisor.
  static Set<BusinessIntent> allowedIntentsFor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return _ownerIntents;
      case UserRole.admin:
        return _adminIntents;
      case UserRole.staff:
        return _staffIntents;
    }
  }

  /// Returns true if [intent] is allowed for [role].
  static bool isAllowed(UserRole role, BusinessIntent intent) {
    return allowedIntentsFor(role).contains(intent);
  }

  /// Returns a human-readable description of what the AI can help with
  /// for the given [role]. Used in system prompts and UI.
  static String capabilityDescription(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'You have access to business-wide analytics: total sales, '
            'product performance, inventory status, low-stock analysis, '
            'category performance, sales trends, recent transactions, '
            'specific product and sale/receipt lookups, cash vs GCash '
            'payment breakdowns, and business recommendations.';
      case UserRole.admin:
        return 'You have access to system administration analytics: user '
            'account summaries and individual user lookups, activity logs, '
            'backup history, export history, and system status. You do '
            'NOT have access to business sales, products, or inventory '
            'analytics.';
      case UserRole.staff:
        return 'You have access to your own sales data, your own sale '
            'receipts, low-stock alerts, product price/stock lookups, '
            'category information, your own cash vs GCash breakdown, and '
            'your own activity. You do NOT have access to other users\' '
            'sales, total business sales, or system administration data.';
    }
  }

  // ── Owner: business-wide analytics ────────────────────────────────────
  static const Set<BusinessIntent> _ownerIntents = {
    BusinessIntent.todaySales,
    BusinessIntent.yesterdaySales,
    BusinessIntent.dateRangeSales,
    BusinessIntent.weeklySales,
    BusinessIntent.monthlySales,
    BusinessIntent.salesComparison,
    BusinessIntent.topProducts,
    BusinessIntent.lowSellingProducts,
    BusinessIntent.productPerformance,
    BusinessIntent.lowStock,
    BusinessIntent.restockRecommendation,
    BusinessIntent.categoryPerformance,
    BusinessIntent.busiestPeriod,
    BusinessIntent.inventoryStatus,
    BusinessIntent.businessSummary,
    BusinessIntent.trendAnalysis,
    BusinessIntent.recentSales,
    BusinessIntent.productLookup,
    BusinessIntent.saleLookup,
    BusinessIntent.paymentBreakdown,
    BusinessIntent.general,
  };

  // ── Admin: system administration analytics ────────────────────────────
  static const Set<BusinessIntent> _adminIntents = {
    BusinessIntent.activeUserSummary,
    BusinessIntent.userStatusSummary,
    BusinessIntent.systemActivitySummary,
    BusinessIntent.recentActivity,
    BusinessIntent.backupSummary,
    BusinessIntent.exportSummary,
    BusinessIntent.systemStatusSummary,
    BusinessIntent.adminSummary,
    BusinessIntent.userLookup,
    BusinessIntent.general,
  };

  // ── Staff: own-data analytics (filtered by currentUserId) ─────────────
  static const Set<BusinessIntent> _staffIntents = {
    BusinessIntent.myTodaySales,
    BusinessIntent.myDateRangeSales,
    BusinessIntent.myRecentSales,
    BusinessIntent.myTopSoldProducts,
    BusinessIntent.lowStock,
    BusinessIntent.productInformation,
    BusinessIntent.categoryInformation,
    BusinessIntent.myActivitySummary,
    BusinessIntent.myWorkSummary,
    BusinessIntent.productLookup,
    BusinessIntent.saleLookup,
    BusinessIntent.paymentBreakdown,
    BusinessIntent.general,
  };
}
