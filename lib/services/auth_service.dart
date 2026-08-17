import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication service.
///
/// Owns login / logout / session-restore logic and user-management
/// operations. The currently authenticated user is stored in the
/// [SessionManager] singleton so that other services can read it without
/// instantiating [AuthService] (which previously caused a circular
/// dependency and Stack Overflow).
class AuthService {
  final UserRepository _userRepository = UserRepository();
  final ActivityLogService _activityLogService = ActivityLogService();
  final SessionManager _sessionManager = SessionManager();
  static const String _sessionKey = 'user_session';

  User? get currentUser => _sessionManager.currentUser;
  bool get isAuthenticated => _sessionManager.isAuthenticated;

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

    _sessionManager.setCurrentUser(user);
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

    _sessionManager.setCurrentUser(user);
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);

    return true;
  }

  Future<void> logout() async {
    _sessionManager.clearCurrentUser();
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

    _sessionManager.setCurrentUser(user);
    return true;
  }

  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }

  bool hasPermission(String permission) {
    return _sessionManager.hasPermission(permission);
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
    if (_sessionManager.currentUser?.id != userId && !hasPermission('reset_password')) {
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
    if (_sessionManager.currentUser?.id == userId && !isActive) {
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
