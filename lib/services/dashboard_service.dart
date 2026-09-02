import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/backup_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// Analytics DTOs
//
// These are derived, read-only analytics shapes. They are NOT persisted
// entities and have no DAO/table of their own; they aggregate real SQLite
// rows fetched through the repositories.
// ─────────────────────────────────────────────────────────────────────────

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
class OwnerDashboardData {
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

/// Aggregated System Admin dashboard data. All values come from real
/// SQLite rows.
class AdminDashboardData {
  final SalesAnalytics? analytics;
  final int activeUsers;
  final int inactiveUsers;
  final int recentActivityCount;
  final UserRoleDistribution usersByRole;
  final BackupSummary backupStatus;
  final int trashCount;
  final List<ActivityLog> recentActivities;

  const AdminDashboardData({
    this.analytics,
    required this.activeUsers,
    required this.inactiveUsers,
    required this.recentActivityCount,
    required this.usersByRole,
    required this.backupStatus,
    required this.trashCount,
    required this.recentActivities,
  });
}

/// Aggregated Staff dashboard data. Sales figures are filtered to the
/// current user only (sales.user_id = currentUser.id).
class StaffDashboardData {
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
  final TrashRepository _trashRepository = TrashRepository();
  final SessionManager _sessionManager = SessionManager();
  final SalesAnalyticsService _salesAnalyticsService = SalesAnalyticsService();

  /// Dispatches to the correct role-scoped loader for the selected period.
  ///
  /// Returns null when the current user lacks `view_dashboard` (defence in
  /// depth — the UI should also be hidden, but this prevents any data leak
  /// if it is not).
  Future<Object?> getDashboard(
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

    // Recent activity (Owner sees all).
    final activities = await _activityLogRepository.getRecentActivities();
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

    // Recent activity count (last 7 days) + 5 most recent.
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekActivities =
        await _activityLogRepository.getByDateRange(weekAgo, now);
    final recentActivities =
        (await _activityLogRepository.getRecentActivities()).take(5).toList();

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

    // Operational sales analytics when the role is permitted to view reports.
    SalesAnalytics? analytics;
    if (_sessionManager.hasPermission('view_reports')) {
      final bounds = periodBoundsFor(
        period,
        customStart: customStart,
        customEnd: customEnd,
      );
      analytics = await _salesAnalyticsService.getAnalyticsForBounds(bounds);
    }

    return AdminDashboardData(
      analytics: analytics,
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
