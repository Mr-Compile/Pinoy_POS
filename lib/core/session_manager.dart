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
  bool _sessionLocked = false;

  /// The currently authenticated user, or null when logged out.
  User? get currentUser => _currentUser;

  /// Whether a user is currently authenticated.
  bool get isAuthenticated => _currentUser != null;

  /// Whether the session is in a non-fully-authenticated phase (PIN lock or
  /// forced password change). While locked, [hasPermission] always returns
  /// false even though [currentUser] is still populated — the user record is
  /// kept so the PIN/password-change flows can resolve it.
  bool get isSessionLocked => _sessionLocked;

  /// Sets the currently authenticated user. Called by [AuthService] after a
  /// successful login or session restore. A fresh user starts unlocked; the
  /// caller applies [setSessionLocked] when the auth phase requires it.
  void setCurrentUser(User user) {
    _currentUser = user;
    _sessionLocked = false;
  }

  /// Clears the currently authenticated user. Called by [AuthService] on
  /// logout or when a session is invalidated.
  void clearCurrentUser() {
    _currentUser = null;
    _sessionLocked = false;
  }

  /// Marks the session as locked (PIN lock / forced password change) or
  /// unlocked. Called by the auth layer when the auth phase transitions.
  void setSessionLocked(bool locked) {
    _sessionLocked = locked;
  }

  /// Resets the singleton state for testing.
  @visibleForTesting
  static void resetForTest() {
    _instance._currentUser = null;
    _instance._sessionLocked = false;
  }

  /// Returns true if the current user has the given [permission].
  ///
  /// Permission lists are role-based and mirror the RBAC policy owned by
  /// [AuthService]. Centralizing them here allows any service to perform
  /// authorization checks without depending on [AuthService].
  bool hasPermission(String permission) {
    final user = _currentUser;
    if (user == null) return false;
    // A locked session (PIN lock / forced password change) must not satisfy
    // service-level permission checks — only the auth flow itself may run.
    if (_sessionLocked) return false;

    switch (user.role) {
      case UserRole.owner:
        return _ownerPermissions.contains(permission);
      case UserRole.admin:
        return _systemAdminPermissions.contains(permission);
      case UserRole.staff:
        return _staffPermissions.contains(permission);
    }
  }

  /// Whether the current user is the business Owner and can manage
  /// business-specific settings such as store information and payment
  /// configuration. This is role-based (Owner), not permission-based, because
  /// the Owner and System Admin both have `edit_settings`.
  bool canEditBusinessSettings() {
    return _currentUser?.role == UserRole.owner &&
        hasPermission('edit_settings');
  }

  /// Owner (Business Owner) — manages store operations, business decisions,
  /// and business continuity. The Owner uses the AI Business Advisor for
  /// business-wide analytics (sales, products, inventory, trends).
  ///
  /// Staff account lifecycle runs entirely through `manage_staff` and
  /// [StaffService] (create, edit, reset password, activate, delete,
  /// restore). The Owner does NOT hold `manage_users` / `edit_users` /
  /// `reset_password` / `toggle_user_active` — those are Admin-surface
  /// permissions enforced by [UserService] and were removed as dead grants.
  ///
  /// `view_users`, `delete_users`, `restore_trash`, and `empty_trash` are
  /// retained because they are load-bearing for the user-trash lifecycle:
  /// `StaffService.softDeleteStaff` -> `TrashService.moveToTrash('user')`
  /// requires `delete_users`, restore requires `view_users`, and the Trash
  /// screen's Users tab is gated on `view_users`.
  ///
  /// System administration tasks (backups, AI configuration / quota,
  /// session timeout, and global system settings) are reserved for the
  /// System Admin role.
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
    'view_payment_evidence',
    'verify_payments',
    'view_reports',
    'export_reports',
    'view_announcements',
    'manage_announcements',
    'view_trash',
    'restore_trash',
    'view_activity_logs',
    'view_ai_advisor',
    'use_ai_advisor',
    // view_settings = system-settings destinations (dashboard quick action,
    // AI nav 'settings', SettingsService.getSettings). SettingsScreen itself
    // is a universal hub for all roles; each system tile gates individually.
    'view_settings',
    'edit_settings',
    'manage_staff',
    'view_staff_performance',
    'view_notifications',
    'view_profile',
    'view_more',
    'view_report_submissions',
    'delete_users',
    'view_users',
    'empty_trash',
  ];

  /// System Admin (IT / System Administration) — maintains the application,
  /// user accounts, backups, and system configuration. Does NOT have access to
  /// POS, products, categories, stock, sales, business reports, business
  /// analytics, or announcements.
  ///
  /// System Admin manages backups (`backup_restore`), AI configuration
  /// (`manage_ai_config`), AI quotas (`manage_ai_quota`), and global session
  /// timeout (`manage_session_settings`).
  ///
  /// The Admin has no `verify_payments` grant: Owner is the only authorized
  /// verifier for Staff-tendered GCash payments (see
  /// [PaymentVerificationService.canRoleVerify]). The previous grant was a
  /// dead permission — Admin could never actually confirm or reject.
  ///
  /// AI access: Admin can CONFIGURE the Groq AI integration
  /// (`manage_ai_config`) and USE the AI System Assistant (`use_ai_advisor`)
  /// for system administration insights. Admin cannot see business sales or
  /// inventory data through the AI; intents are scoped by
  /// [AICapabilityPolicy].
  static const List<String> _systemAdminPermissions = [
    'view_dashboard',
    'manage_users',
    'edit_users',
    'delete_users',
    'reset_password',
    'toggle_user_active',
    // view_settings = system-settings destinations (dashboard quick action,
    // AI nav 'settings', SettingsService.getSettings). SettingsScreen itself
    // is a universal hub for all roles; each system tile gates individually.
    'view_settings',
    'edit_settings',
    'backup_restore',
    'manage_ai_config',
    'manage_ai_quota',
    'manage_session_settings',
    'view_ai_advisor',
    'use_ai_advisor',
    'view_trash',
    'restore_trash',
    'view_activity_logs',
    'view_notifications',
    'view_profile',
    'view_more',
    'view_users',
  ];

  /// Staff (Operational User) — daily cashier and inventory operations.
  /// Can view products/categories, add stock, create sales, view own
  /// sales/reports, and manage their own profile.
  ///
  /// Catalog writes are Owner-only: Staff hold `view_categories` for
  /// read-only browsing but not `change_category_status` — toggling a
  /// category active/inactive mutates the catalog and hides its products
  /// from POS, which is not a cashier responsibility.
  ///
  /// `submit_reports` is Staff-only by business rule: Staff generate and
  /// submit reports to the Owner. The Owner reviews submissions and must
  /// never be treated as a report author/submitter.
  ///
  /// AI access: Staff can use the AI Work Assistant (`use_ai_advisor`)
  /// for their own sales, low-stock alerts, product information, and daily
  /// work activity. Staff cannot see other users' sales, total business
  /// sales, or system configuration through the AI; intents are scoped by
  /// [AICapabilityPolicy].
  static const List<String> _staffPermissions = [
    'view_dashboard',
    'view_pos',
    'view_products',
    'view_categories',
    'view_stock',
    'add_stock',
    'view_sales',
    'create_sales',
    'view_reports',
    'export_reports',
    'submit_reports',
    'view_ai_advisor',
    'use_ai_advisor',
    'view_notifications',
    'view_activity_logs',
    'view_profile',
    'view_more',
  ];
}
