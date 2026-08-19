import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/backup_history_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

// ─────────────────────────────────────────────────────────────────────────
// Analytics DTOs
//
// These are derived, read-only analytics shapes. They are NOT persisted
// entities and have no DAO/table of their own; they aggregate real SQLite
// rows fetched through the repositories.
// ─────────────────────────────────────────────────────────────────────────

/// One day's aggregated sales total + transaction count.
class DailySalesPoint {
  final DateTime date;
  final double total;
  final int transactionCount;

  const DailySalesPoint({
    required this.date,
    required this.total,
    required this.transactionCount,
  });
}

/// A product ranked by total quantity sold.
class TopProductStat {
  final int productId;
  final String name;
  final int totalQuantity;

  const TopProductStat({
    required this.productId,
    required this.name,
    required this.totalQuantity,
  });
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
class OwnerDashboardData {
  final double todaySales;
  final int todayTransactions;
  final int lowStockCount;
  final int outOfStockCount;
  final List<DailySalesPoint> salesTrend;
  final List<TopProductStat> topProducts;
  final InventoryStatus inventoryStatus;
  final List<Sale> recentSales;
  final List<ActivityLog> recentActivities;
  final List<Announcement> announcements;
  final List<Product> lowStockProducts;

  const OwnerDashboardData({
    required this.todaySales,
    required this.todayTransactions,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.salesTrend,
    required this.topProducts,
    required this.inventoryStatus,
    required this.recentSales,
    required this.recentActivities,
    required this.announcements,
    required this.lowStockProducts,
  });
}

/// Aggregated System Admin dashboard data. All values come from real
/// SQLite rows. Contains NO business/POS analytics.
class AdminDashboardData {
  final int activeUsers;
  final int inactiveUsers;
  final int recentActivityCount;
  final UserRoleDistribution usersByRole;
  final BackupSummary backupStatus;
  final int trashCount;
  final List<ActivityLog> recentActivities;

  const AdminDashboardData({
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
  final double mySalesToday;
  final int myTransactionsToday;
  final int lowStockCount;
  final int outOfStockCount;
  final List<DailySalesPoint> mySalesTrend;
  final InventoryStatus inventoryStatus;
  final List<Sale> myRecentSales;
  final List<ActivityLog> recentActivities;
  final List<Product> lowStockProducts;

  const StaffDashboardData({
    required this.mySalesToday,
    required this.myTransactionsToday,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.mySalesTrend,
    required this.inventoryStatus,
    required this.myRecentSales,
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
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final ProductRepository _productRepository = ProductRepository();
  final UserRepository _userRepository = UserRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final AnnouncementRepository _announcementRepository = AnnouncementRepository();
  final BackupHistoryRepository _backupHistoryRepository = BackupHistoryRepository();
  final TrashRepository _trashRepository = TrashRepository();
  final SessionManager _sessionManager = SessionManager();

  /// Dispatches to the correct role-scoped loader. Returns null when the
  /// current user lacks `view_dashboard` (defence in depth — the UI should
  /// also be hidden, but this prevents any data leak if it is not).
  Future<Object?> getDashboard() async {
    if (!_sessionManager.hasPermission('view_dashboard')) {
      return null;
    }
    final role = _sessionManager.currentUser?.role;
    switch (role) {
      case UserRole.owner:
        return getOwnerDashboard();
      case UserRole.admin:
        return getAdminDashboard();
      case UserRole.staff:
        return getStaffDashboard();
      case null:
        return null;
    }
  }

  // ── Owner ──────────────────────────────────────────────────────────

  Future<OwnerDashboardData> getOwnerDashboard() async {
    if (!_sessionManager.hasPermission('view_dashboard')) {
      return _emptyOwner();
    }

    final now = DateTime.now();
    final trendStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final trendEnd = trendStart.add(const Duration(days: 7));

    // Fetch non-voided sales across the last 7 days for the trend + today's
    // totals + recent sales list. A single query feeds multiple metrics.
    final trendSales = await _saleRepository.getByDateRange(trendStart, trendEnd);
    final salesTrend = _buildDailySalesTrend(trendSales, trendStart);

    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todaySales = trendSales
        .where((s) => !s.createdAt.isBefore(todayStart) && s.createdAt.isBefore(todayEnd))
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final todayTransactions = trendSales
        .where((s) => !s.createdAt.isBefore(todayStart) && s.createdAt.isBefore(todayEnd))
        .length;

    // Inventory status from active products.
    final products = await _productRepository.getActiveProducts();
    final inventory = _computeInventoryStatus(products);
    final lowStockProducts = products
        .where((p) => p.stock > 0 && p.stock <= p.minStock)
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    // Top products over the last 30 days (business-wide).
    final topSince = now.subtract(const Duration(days: 30));
    final topRows = await _saleItemRepository.getTopProductsByQuantity(
      limit: 5,
      since: topSince,
    );
    final topProducts = topRows.map(_mapTopProduct).toList();

    // Recent sales (newest first, already ordered DESC by the DAO).
    final recentSales = trendSales.take(5).toList();

    // Recent activity (Owner sees all).
    final activities = await _activityLogRepository.getRecentActivities();
    final recentActivities = activities.take(5).toList();

    // Active announcements, pinned first.
    final announcements = await _loadAnnouncements();

    return OwnerDashboardData(
      todaySales: todaySales,
      todayTransactions: todayTransactions,
      lowStockCount: inventory.lowStock,
      outOfStockCount: inventory.outOfStock,
      salesTrend: salesTrend,
      topProducts: topProducts,
      inventoryStatus: inventory,
      recentSales: recentSales,
      recentActivities: recentActivities,
      announcements: announcements,
      lowStockProducts: lowStockProducts,
    );
  }

  // ── Admin ──────────────────────────────────────────────────────────

  Future<AdminDashboardData> getAdminDashboard() async {
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
      recentActivities: recentActivities,
    );
  }

  // ── Staff ──────────────────────────────────────────────────────────

  Future<StaffDashboardData> getStaffDashboard() async {
    final user = _sessionManager.currentUser;
    if (!_sessionManager.hasPermission('view_dashboard') || user == null) {
      return _emptyStaff();
    }
    final userId = user.id!;

    final now = DateTime.now();
    final trendStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final trendEnd = trendStart.add(const Duration(days: 7));

    // Staff: only own sales (filtered at the DAO query level).
    final trendSales = await _saleRepository.getByDateRangeAndUser(
      trendStart,
      trendEnd,
      userId,
    );
    final salesTrend = _buildDailySalesTrend(trendSales, trendStart);

    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final myTodaySales = trendSales
        .where((s) => !s.createdAt.isBefore(todayStart) && s.createdAt.isBefore(todayEnd))
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final myTodayTransactions = trendSales
        .where((s) => !s.createdAt.isBefore(todayStart) && s.createdAt.isBefore(todayEnd))
        .length;

    // Inventory status (Staff may view products/stock).
    final products = await _productRepository.getActiveProducts();
    final inventory = _computeInventoryStatus(products);
    final lowStockProducts = products
        .where((p) => p.stock > 0 && p.stock <= p.minStock)
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    // Staff recent sales (own only).
    final myRecentSales = trendSales.take(5).toList();

    // Staff recent activity (own only — DAO filters by user_id).
    final activities = await _activityLogRepository.getByUserId(userId);
    final recentActivities = activities.take(5).toList();

    return StaffDashboardData(
      mySalesToday: myTodaySales,
      myTransactionsToday: myTodayTransactions,
      lowStockCount: inventory.lowStock,
      outOfStockCount: inventory.outOfStock,
      mySalesTrend: salesTrend,
      inventoryStatus: inventory,
      myRecentSales: myRecentSales,
      recentActivities: recentActivities,
      lowStockProducts: lowStockProducts,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Builds a 7-point daily sales trend starting at [start] (inclusive),
  /// one point per day, aggregating [sales] by calendar day. Days with no
  /// sales produce a zero point so the chart axis stays consistent.
  List<DailySalesPoint> _buildDailySalesTrend(List<Sale> sales, DateTime start) {
    final byDay = <int, List<Sale>>{};
    for (final s in sales) {
      final key = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day)
          .millisecondsSinceEpoch;
      byDay.putIfAbsent(key, () => []).add(s);
    }
    final points = <DailySalesPoint>[];
    for (int i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final key = day.millisecondsSinceEpoch;
      final daySales = byDay[key] ?? const [];
      points.add(DailySalesPoint(
        date: day,
        total: daySales.fold<double>(0.0, (sum, s) => sum + s.totalAmount),
        transactionCount: daySales.length,
      ));
    }
    return points;
  }

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

  TopProductStat _mapTopProduct(Map<String, dynamic> row) {
    return TopProductStat(
      productId: (row['product_id'] as num?)?.toInt() ?? 0,
      name: (row['product_name'] as String?) ?? 'Unknown',
      totalQuantity: (row['total_quantity'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Empty states (returned when permission is missing) ─────────────

  OwnerDashboardData _emptyOwner() => const OwnerDashboardData(
        todaySales: 0,
        todayTransactions: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        salesTrend: [],
        topProducts: [],
        inventoryStatus: InventoryStatus(normal: 0, lowStock: 0, outOfStock: 0),
        recentSales: [],
        recentActivities: [],
        announcements: [],
        lowStockProducts: [],
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

  StaffDashboardData _emptyStaff() => const StaffDashboardData(
        mySalesToday: 0,
        myTransactionsToday: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        mySalesTrend: [],
        inventoryStatus: InventoryStatus(normal: 0, lowStock: 0, outOfStock: 0),
        myRecentSales: [],
        recentActivities: [],
        lowStockProducts: [],
      );
}
