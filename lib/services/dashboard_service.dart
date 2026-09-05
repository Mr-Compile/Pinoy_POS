import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/data/repositories/ai_quota_repository.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/backup_history_repository.dart';
import 'package:pinoy_pos/data/repositories/export_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// Analytics DTOs
//
// These are derived, read-only analytics shapes. They are NOT persisted
// entities and have no DAO/table of their own; they aggregate real SQLite
// rows fetched through the repositories.
// ─────────────────────────────────────────────────────────────────────────

/// Base type for the role-scoped dashboard payloads returned by
/// [DashboardService.getDashboard].
///
/// The UI switches on the concrete subtype rather than the live session
/// role, so an account change that lands while a load is in flight cannot
/// pair the new role with the previous role's data.
sealed class DashboardData {
  const DashboardData();
}

/// Inventory health distribution across active products.
class InventoryStatus {
  final int normal;
  final int lowStock;
  final int outOfStock;

  const InventoryStatus({
    required this.normal,
    required this.lowStock,
    required this.outOfStock,
  });

  int get total => normal + lowStock + outOfStock;
}

/// User count distribution by role (non-deleted users only).
class UserRoleDistribution {
  final int owner;
  final int admin;
  final int staff;

  const UserRoleDistribution({
    required this.owner,
    required this.admin,
    required this.staff,
  });

  int get total => owner + admin + staff;
}

/// Summary of the most recent backup record.
class BackupSummary {
  final bool hasBackup;
  final DateTime? lastBackupDate;

  const BackupSummary({required this.hasBackup, this.lastBackupDate});
}

/// Aggregated Owner dashboard data. All values come from real SQLite rows.
class OwnerDashboardData extends DashboardData {
  final SalesAnalytics analytics;
  final int lowStockCount;
  final int outOfStockCount;
  final InventoryStatus inventoryStatus;
  final List<Sale> recentSales;
  final List<ActivityLog> recentActivities;
  final List<Announcement> announcements;
  final List<Product> lowStockProducts;

  const OwnerDashboardData({
    required this.analytics,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.inventoryStatus,
    required this.recentSales,
    required this.recentActivities,
    required this.announcements,
    required this.lowStockProducts,
  });
}

/// Aggregated System Admin dashboard data. System/maintenance metrics only —
/// the Admin role has no `view_reports` permission and never receives
/// business sales analytics. All values come from real SQLite rows.
class AdminDashboardData extends DashboardData {
  final int activeUsers;
  final int inactiveUsers;
  final int recentActivityCount;
  final UserRoleDistribution usersByRole;
  final BackupSummary backupStatus;
  final int trashCount;
  final int exportCount;
  final DateTime? lastExportAt;
  final bool aiConfigured;
  final String aiModel;
  final int aiQueriesToday;
  final List<ActivityLog> recentActivities;

  const AdminDashboardData({
    required this.activeUsers,
    required this.inactiveUsers,
    required this.recentActivityCount,
    required this.usersByRole,
    required this.backupStatus,
    required this.trashCount,
    required this.exportCount,
    this.lastExportAt,
    required this.aiConfigured,
    required this.aiModel,
    required this.aiQueriesToday,
    required this.recentActivities,
  });
}

/// Aggregated Staff dashboard data. Sales figures are filtered to the
/// current user only (sales.user_id = currentUser.id).
class StaffDashboardData extends DashboardData {
  final SalesAnalytics analytics;
  final int lowStockCount;
  final int outOfStockCount;
  final InventoryStatus inventoryStatus;
  final List<ActivityLog> recentActivities;
  final List<Product> lowStockProducts;

  const StaffDashboardData({
    required this.analytics,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.inventoryStatus,
    required this.recentActivities,
    required this.lowStockProducts,
  });
}

/// Centralised dashboard analytics service.
///
/// Architecture:
///
///     UI → DashboardProvider → DashboardService → Repository → DAO → SQLite
///
/// The service is authoritative for role-based data scoping:
///   - Owner: permitted business-wide analytics.
///   - Admin: system analytics only (users, activity, backup, trash).
///   - Staff: own sales only (WHERE user_id = currentUser.id) + viewable
///     inventory status.
///
/// UI hiding is NOT a security mechanism; the service enforces the same
/// RBAC as [SessionManager] and filters Staff data at the query level.
class DashboardService {
  final ProductRepository _productRepository = ProductRepository();
  final UserRepository _userRepository = UserRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final AnnouncementRepository _announcementRepository = AnnouncementRepository();
  final BackupHistoryRepository _backupHistoryRepository = BackupHistoryRepository();
  final ExportHistoryRepository _exportHistoryRepository = ExportHistoryRepository();
  final AIQuotaRepository _aiQuotaRepository = AIQuotaRepository();
  final TrashRepository _trashRepository = TrashRepository();
  final SessionManager _sessionManager = SessionManager();
  final SalesAnalyticsService _salesAnalyticsService = SalesAnalyticsService();
  final SettingsService _settingsService = SettingsService();

  /// Dispatches to the correct role-scoped loader for the selected period.
  ///
  /// Returns null when there is no authenticated user or the current user
  /// lacks `view_dashboard` (defence in depth — the UI should also be
  /// hidden, but this prevents any data leak if it is not). The caller
  /// distinguishes the two cases via the current authentication state.
  Future<DashboardData?> getDashboard(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_sessionManager.hasPermission('view_dashboard')) {
      return null;
    }
    final role = _sessionManager.currentUser?.role;
    switch (role) {
      case UserRole.owner:
        return getOwnerDashboard(period, customStart: customStart, customEnd: customEnd);
      case UserRole.admin:
        return getAdminDashboard(period, customStart: customStart, customEnd: customEnd);
      case UserRole.staff:
        return getStaffDashboard(period, customStart: customStart, customEnd: customEnd);
      case null:
        return null;
    }
  }

  // ── Owner ──────────────────────────────────────────────────────────

  Future<OwnerDashboardData> getOwnerDashboard(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_sessionManager.hasPermission('view_dashboard')) {
      return _emptyOwner();
    }

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    final analytics = await _salesAnalyticsService.getAnalyticsForBounds(bounds);

    // Inventory status from active products.
    final products = await _productRepository.getActiveProducts();
    final inventory = _computeInventoryStatus(products);
    final lowStockProducts = products
        .where((p) => p.stock > 0 && p.stock <= p.minStock)
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    // Recent activity (Owner sees own actions only; dashboard is a personal view).
    final activities = await _activityLogRepository.getByUserId(
      _sessionManager.currentUser!.id!,
    );
    final recentActivities = activities.take(5).toList();

    // Active announcements, pinned first.
    final announcements = await _loadAnnouncements();

    return OwnerDashboardData(
      analytics: analytics,
      lowStockCount: inventory.lowStock,
      outOfStockCount: inventory.outOfStock,
      inventoryStatus: inventory,
      recentSales: analytics.sales.take(5).toList(),
      recentActivities: recentActivities,
      announcements: announcements,
      lowStockProducts: lowStockProducts,
    );
  }

  // ── Admin ──────────────────────────────────────────────────────────

  /// Admin dashboard is system/maintenance only. The [period],
  /// [customStart], and [customEnd] parameters are accepted for interface
  /// symmetry with the other loaders but are unused — no Admin metric is
  /// driven by the period selector.
  Future<AdminDashboardData> getAdminDashboard(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (!_sessionManager.hasPermission('view_dashboard')) {
      return _emptyAdmin();
    }

    // Users: active vs inactive (non-deleted only).
    final activeUsers = await _userRepository.getActiveUsers();
    final allNonDeleted = await _userRepository.getAllActive();
    final inactiveCount = allNonDeleted.length - activeUsers.length;

    // Users by role.
    final owners = await _userRepository.getByRole(UserRole.owner);
    final admins = await _userRepository.getByRole(UserRole.admin);
    final staff = await _userRepository.getByRole(UserRole.staff);

    // Recent activity count (last 7 days) + 5 most recent — scoped to the
    // current admin user so each admin sees only their own system activity.
    final currentUser = _sessionManager.currentUser;
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekActivities = currentUser?.id == null
        ? <ActivityLog>[]
        : await _activityLogRepository.getByUserIdAndDateRange(
            currentUser!.id!,
            weekAgo,
            now,
          );
    final recentActivities = currentUser?.id == null
        ? <ActivityLog>[]
        : (await _activityLogRepository.getByUserId(currentUser!.id!))
            .take(5)
            .toList();

    // Backup status from backup_history (real DB rows, not filesystem scan).
    final backups = await _backupHistoryRepository.getAll();
    BackupSummary backupSummary;
    if (backups.isEmpty) {
      backupSummary = const BackupSummary(hasBackup: false);
    } else {
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      backupSummary =
          BackupSummary(hasBackup: true, lastBackupDate: backups.first.createdAt);
    }

    // Trash count.
    final trashItems = await _trashRepository.getAll();

    // Export history summary (non-deleted rows, newest first).
    final exports = await _exportHistoryRepository.getAllActive(limit: 200);

    // AI service status: whether a Groq API key is configured, which model
    // is selected, and how many queries active users have run today.
    // Best-effort — secure storage can throw on platforms without a
    // keychain (e.g. tests); an AI status failure must not take the whole
    // dashboard down.
    var aiConfigured = false;
    var aiModel = '';
    try {
      aiConfigured = await _settingsService.isGroqConfigured();
      if (aiConfigured) {
        aiModel = await _settingsService.getGroqModel();
      }
    } catch (_) {
      // Leave the card in its "not configured" state.
    }
    final quotas = await _aiQuotaRepository.getForActiveUsers();
    final aiQueriesToday = quotas
        .where((q) =>
            q.quotaDate.year == now.year &&
            q.quotaDate.month == now.month &&
            q.quotaDate.day == now.day)
        .fold<int>(0, (sum, q) => sum + q.dailyUsage);

    return AdminDashboardData(
      activeUsers: activeUsers.length,
      inactiveUsers: inactiveCount < 0 ? 0 : inactiveCount,
      recentActivityCount: weekActivities.length,
      usersByRole: UserRoleDistribution(
        owner: owners.length,
        admin: admins.length,
        staff: staff.length,
      ),
      backupStatus: backupSummary,
      trashCount: trashItems.length,
      exportCount: exports.length,
      lastExportAt: exports.isEmpty ? null : exports.first.createdAt,
      aiConfigured: aiConfigured,
      aiModel: aiModel,
      aiQueriesToday: aiQueriesToday,
      recentActivities: recentActivities,
    );
  }

  // ── Staff ──────────────────────────────────────────────────────────

  Future<StaffDashboardData> getStaffDashboard(
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final user = _sessionManager.currentUser;
    if (!_sessionManager.hasPermission('view_dashboard') || user == null) {
      return _emptyStaff();
    }

    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    // SalesAnalyticsService automatically scopes Staff to the current user.
    final analytics = await _salesAnalyticsService.getAnalyticsForBounds(bounds);

    // Inventory status (Staff may view products/stock).
    final products = await _productRepository.getActiveProducts();
    final inventory = _computeInventoryStatus(products);
    final lowStockProducts = products
        .where((p) => p.stock > 0 && p.stock <= p.minStock)
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    // Staff recent activity (own only — DAO filters by user_id).
    final activities = await _activityLogRepository.getByUserId(user.id!);
    final recentActivities = activities.take(5).toList();

    return StaffDashboardData(
      analytics: analytics,
      lowStockCount: inventory.lowStock,
      outOfStockCount: inventory.outOfStock,
      inventoryStatus: inventory,
      recentActivities: recentActivities,
      lowStockProducts: lowStockProducts,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Computes inventory status from a list of active products.
  ///
  /// Status logic:
  ///   OUT OF STOCK: stock <= 0
  ///   LOW STOCK:    stock > 0 AND stock <= minStock
  ///   NORMAL:       stock > minStock
  InventoryStatus _computeInventoryStatus(List<Product> products) {
    int normal = 0, low = 0, out = 0;
    for (final p in products) {
      if (p.stock <= 0) {
        out++;
      } else if (p.stock <= p.minStock) {
        low++;
      } else {
        normal++;
      }
    }
    return InventoryStatus(normal: normal, lowStock: low, outOfStock: out);
  }

  /// Loads active announcements sorted pinned-first, then by created_at desc.
  Future<List<Announcement>> _loadAnnouncements() async {
    if (!_sessionManager.hasPermission('view_announcements')) {
      return [];
    }
    final items = await _announcementRepository.getActiveAnnouncements();
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  // ── Empty states (returned when permission is missing) ─────────────

  OwnerDashboardData _emptyOwner() => OwnerDashboardData(
        analytics: SalesAnalytics.empty(
          ReportingPeriodBounds(
            start: DateTime.now(),
            end: DateTime.now(),
            previousStart: DateTime.now(),
            previousEnd: DateTime.now(),
            groupBy: ReportGroupBy.day,
          ),
        ),
        lowStockCount: 0,
        outOfStockCount: 0,
        inventoryStatus:
            const InventoryStatus(normal: 0, lowStock: 0, outOfStock: 0),
        recentSales: const [],
        recentActivities: const [],
        announcements: const [],
        lowStockProducts: const [],
      );

  AdminDashboardData _emptyAdmin() => const AdminDashboardData(
        activeUsers: 0,
        inactiveUsers: 0,
        recentActivityCount: 0,
        usersByRole: UserRoleDistribution(owner: 0, admin: 0, staff: 0),
        backupStatus: BackupSummary(hasBackup: false),
        trashCount: 0,
        exportCount: 0,
        aiConfigured: false,
        aiModel: '',
        aiQueriesToday: 0,
        recentActivities: [],
      );

  StaffDashboardData _emptyStaff() => StaffDashboardData(
        analytics: SalesAnalytics.empty(
          ReportingPeriodBounds(
            start: DateTime.now(),
            end: DateTime.now(),
            previousStart: DateTime.now(),
            previousEnd: DateTime.now(),
            groupBy: ReportGroupBy.day,
          ),
        ),
        lowStockCount: 0,
        outOfStockCount: 0,
        inventoryStatus:
            const InventoryStatus(normal: 0, lowStock: 0, outOfStock: 0),
        recentActivities: const [],
        lowStockProducts: const [],
      );
}
