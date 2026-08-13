import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final UserRepository _userRepository = UserRepository();
  final ActivityLogService _activityLogService = ActivityLogService();
  User? _currentUser;
  static const String _sessionKey = 'user_session';

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<bool> login(String username, String password) async {
    final user = await _userRepository.getByUsername(username);
    
    if (user == null) {
      return false;
    }

    if (!user.isActive) {
      return false;
    }

    if (!SecurityHelper.verifyPassword(password, user.passwordHash)) {
      return false;
    }

    _currentUser = user;
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);
    
    return true;
  }

  Future<bool> loginWithPin(String username, String pin) async {
    final user = await _userRepository.getByUsername(username);
    
    if (user == null || user.pin == null) {
      return false;
    }

    if (!user.isActive) {
      return false;
    }

    if (user.pin != pin) {
      return false;
    }

    _currentUser = user;
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);
    
    return true;
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionKey);
    
    if (userId == null) {
      return false;
    }

    final user = await _userRepository.getById(userId);
    
    if (user == null || !user.isActive || user.isDeleted) {
      await logout();
      return false;
    }

    _currentUser = user;
    return true;
  }

  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }

  bool hasPermission(String permission) {
    if (_currentUser == null) return false;

    switch (_currentUser!.role) {
      case UserRole.owner:
        return _getOwnerPermissions().contains(permission);
      case UserRole.admin:
        return _getSystemAdminPermissions().contains(permission);
      case UserRole.staff:
        return _getStaffPermissions().contains(permission);
    }
  }

  /// Owner (Business Superuser) — manages store operations and business
  /// decisions. Does NOT have user management, backup/restore, or system
  /// maintenance access.
  List<String> _getOwnerPermissions() {
    return [
      'view_dashboard',
      'view_pos',
      'view_products',
      'edit_products',
      'delete_products',
      'view_categories',
      'edit_categories',
      'delete_categories',
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
  }

  /// System Admin (Technical Administrator) — maintains the application,
  /// accounts, backups, and system configuration. Does NOT have access to
  /// POS, products, categories, stock, sales, reports, announcements, or AI
  /// advisor.
  List<String> _getSystemAdminPermissions() {
    return [
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
  }

  /// Staff (Operational User) — daily cashier and inventory operations.
  /// Can view products/categories, add stock, create sales, view own
  /// sales/reports, and manage their own profile.
  List<String> _getStaffPermissions() {
    return [
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
      'view_notifications',
      'view_activity_logs',
      'view_profile',
      'view_more',
    ];
  }

  Future<bool> createUser({
    required String username,
    required String password,
    required String fullName,
    required UserRole role,
    String? pin,
  }) async {
    if (!hasPermission('manage_users')) {
      throw AuthorizationException('manage_users');
    }

    final existingUser = await _userRepository.getByUsernameWithDeleted(username);
    if (existingUser != null) {
      return false;
    }

    if (password.length < AppConstants.minPasswordLength) {
      return false;
    }

    final passwordHash = SecurityHelper.hashPassword(password);

    final user = User(
      username: username,
      passwordHash: passwordHash,
      pin: pin,
      role: role,
      fullName: fullName,
      createdAt: DateTime.now(),
    );

    await _userRepository.insert(user);
    await _activityLogService.logActivity(
      action: 'create_user',
      entity: 'user',
      details: 'Created user: $username (${role.displayName})',
    );
    return true;
  }

  Future<bool> changePassword(int userId, String oldPassword, String newPassword) async {
    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    // Users can change their own password; only System Admin can reset others'
    if (_currentUser?.id != userId && !hasPermission('reset_password')) {
      throw AuthorizationException('reset_password');
    }

    if (!SecurityHelper.verifyPassword(oldPassword, user.passwordHash)) {
      return false;
    }

    if (newPassword.length < AppConstants.minPasswordLength) {
      return false;
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(passwordHash: newPasswordHash);
    await _userRepository.update(updatedUser);
    
    return true;
  }

  Future<bool> resetPassword(int userId, String newPassword) async {
    if (!hasPermission('reset_password')) {
      throw AuthorizationException('reset_password');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    if (newPassword.length < AppConstants.minPasswordLength) {
      return false;
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(passwordHash: newPasswordHash);
    await _userRepository.update(updatedUser);

    await _activityLogService.logActivity(
      action: 'reset_password',
      entity: 'user',
      entityId: userId,
      details: 'Password reset for user: ${user.username}',
    );

    return true;
  }

  /// Update a user's profile (full name, role). Only System Admin can update
  /// other users. Users can update their own full name but not their role.
  Future<bool> updateUser({
    required int userId,
    String? fullName,
    UserRole? role,
  }) async {
    if (!hasPermission('edit_users')) {
      throw AuthorizationException('edit_users');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    final updatedUser = user.copyWith(
      fullName: fullName ?? user.fullName,
      role: role ?? user.role,
    );

    await _userRepository.update(updatedUser);

    await _activityLogService.logActivity(
      action: 'update_user',
      entity: 'user',
      entityId: userId,
      details: 'Updated user: ${user.username}',
    );

    return true;
  }

  /// Activate or deactivate a user. Only System Admin can toggle user active
  /// status.
  Future<bool> toggleUserActive(int userId, bool isActive) async {
    if (!hasPermission('toggle_user_active')) {
      throw AuthorizationException('toggle_user_active');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    // Prevent deactivating self
    if (_currentUser?.id == userId && !isActive) {
      return false;
    }

    await _userRepository.toggleActive(userId, isActive);

    await _activityLogService.logActivity(
      action: isActive ? 'activate_user' : 'deactivate_user',
      entity: 'user',
      entityId: userId,
      details: '${isActive ? 'Activated' : 'Deactivated'} user: ${user.username}',
    );

    return true;
  }
}
