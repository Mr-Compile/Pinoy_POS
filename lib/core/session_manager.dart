import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/data/models/user.dart';

/// Singleton holder for the currently authenticated user.
///
/// This decouples the "who is the current user" concern from [AuthService],
/// breaking the previous circular dependency:
///
///     AuthService -> ActivityLogService -> AuthService -> ... (Stack Overflow)
///
/// Dependency direction now:
///
///     AuthService  -> SessionManager  (sets current user on login/restore)
///     Any Service  -> SessionManager  (reads current user / permissions)
///
/// Lower layers (services) never instantiate [AuthService] anymore, so no
/// cycle can form. [SessionManager] depends only on the [User] model.
class SessionManager {
  SessionManager._internal();
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;

  User? _currentUser;

  /// The currently authenticated user, or null when logged out.
  User? get currentUser => _currentUser;

  /// Whether a user is currently authenticated.
  bool get isAuthenticated => _currentUser != null;

  /// Sets the currently authenticated user. Called by [AuthService] after a
  /// successful login or session restore.
  void setCurrentUser(User user) {
    _currentUser = user;
  }

  /// Clears the currently authenticated user. Called by [AuthService] on
  /// logout or when a session is invalidated.
  void clearCurrentUser() {
    _currentUser = null;
  }

  /// Resets the singleton state for testing.
  @visibleForTesting
  static void resetForTest() {
    _instance._currentUser = null;
  }

  /// Returns true if the current user has the given [permission].
  ///
  /// Permission lists are role-based and mirror the RBAC policy owned by
  /// [AuthService]. Centralizing them here allows any service to perform
  /// authorization checks without depending on [AuthService].
  bool hasPermission(String permission) {
    final user = _currentUser;
    if (user == null) return false;

    switch (user.role) {
      case UserRole.owner:
        return _ownerPermissions.contains(permission);
      case UserRole.admin:
        return _systemAdminPermissions.contains(permission);
      case UserRole.staff:
        return _staffPermissions.contains(permission);
    }
  }

  /// Owner (Business Superuser) — manages store operations and business
  /// decisions. Does NOT have user management, backup/restore, or system
  /// maintenance access.
  static const List<String> _ownerPermissions = [
    'view_dashboard',
    'view_pos',
    'view_products',
    'edit_products',
    'delete_products',
    'view_categories',
    'edit_categories',
    'delete_categories',
    'change_category_status',
    'view_stock',
    'add_stock',
    'adjust_stock',
    'view_sales',
    'create_sales',
    'void_sales',
    'view_reports',
    'export_reports',
    'view_announcements',
    'manage_announcements',
    'view_trash',
    'restore_trash',
    'view_activity_logs',
    'view_ai_advisor',
    'view_settings',
    'edit_settings',
    'view_notifications',
    'view_profile',
    'view_more',
  ];

  /// System Admin (Technical Administrator) — maintains the application,
  /// accounts, backups, and system configuration. Does NOT have access to
  /// POS, products, categories, stock, sales, reports, announcements, or AI
  /// advisor.
  static const List<String> _systemAdminPermissions = [
    'view_dashboard',
    'manage_users',
    'edit_users',
    'delete_users',
    'reset_password',
    'toggle_user_active',
    'view_settings',
    'edit_settings',
    'backup_restore',
    'view_trash',
    'restore_trash',
    'view_activity_logs',
    'view_notifications',
    'view_profile',
    'view_more',
  ];

  /// Staff (Operational User) — daily cashier and inventory operations.
  /// Can view products/categories, add stock, create sales, view own
  /// sales/reports, and manage their own profile.
  static const List<String> _staffPermissions = [
    'view_dashboard',
    'view_pos',
    'view_products',
    'view_categories',
    'change_category_status',
    'view_stock',
    'add_stock',
    'view_sales',
    'create_sales',
    'view_reports',
    'export_reports',
    'view_notifications',
    'view_activity_logs',
    'view_profile',
    'view_more',
  ];
}
