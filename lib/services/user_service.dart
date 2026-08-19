import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';

/// Result of a user operation.  Carries a human-readable message and a
/// success flag so the UI layer never needs to interpret raw exceptions.
class UserOperationResult {
  final bool success;
  final String message;
  final User? user;

  UserOperationResult({
    required this.success,
    required this.message,
    this.user,
  });
}

/// User management service.
///
/// Owns all business logic for User Management CRUD:
///   - createUser
///   - updateUser
///   - changePassword
///   - resetUserPassword
///   - activateUser / deactivateUser
///   - softDeleteUser
///   - restoreUser
///   - permanentlyDeleteUser
///
/// Every mutation verifies RBAC permissions via [SessionManager] and logs
/// the action via [ActivityLogService].  The service never touches the UI
/// (no BuildContext, no dialogs, no snackbars).
///
/// Dependency direction:
///
///     UserService -> UserRepository -> UserDao -> SQLite
///     UserService -> ActivityLogService -> ActivityLogRepository -> DAO
///     UserService -> SessionManager (reads current user / permissions)
///
/// There is NO dependency on AuthService, which breaks the previous
/// circular dependency that caused the Riverpod Stack Overflow.
class UserService {
  final UserRepository _userRepository = UserRepository();
  final ActivityLogService _activityLogService = ActivityLogService();
  final SessionManager _sessionManager = SessionManager();

  User? get currentUser => _sessionManager.currentUser;

  /// Validates password complexity.  Mirrors the rules enforced by the UI
  /// [Validators.password] so that business-layer validation does not rely
  /// on the UI alone.  Returns null when valid, or an error message.
  String? _validatePasswordComplexity(String password) {
    if (password.length < AppConstants.minPasswordLength) {
      return 'Password must be at least ${AppConstants.minPasswordLength} characters';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  // ───────────────────────────────────────────────
  //  READ
  // ───────────────────────────────────────────────

  /// Returns all non-deleted users (User Management list).
  Future<List<User>> getAllUsers() async {
    if (!_sessionManager.hasPermission('manage_users')) {
      return [];
    }
    return _userRepository.getAllActive();
  }

  /// Returns all soft-deleted users (Trash list).
  Future<List<User>> getDeletedUsers() async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    return _userRepository.getDeleted();
  }

  /// Returns a single non-deleted user by id.
  Future<User?> getUserById(int id) async {
    if (!_sessionManager.hasPermission('manage_users')) {
      return null;
    }
    return _userRepository.getById(id);
  }

  // ───────────────────────────────────────────────
  //  CREATE
  // ───────────────────────────────────────────────

  /// Creates a new user.
  ///
  /// Validates:
  ///   - Caller has `manage_users` permission
  ///   - Username is non-empty and unique among non-deleted users
  ///   - Full name is non-empty
  ///   - Password meets complexity requirements
  ///   - Role is valid
  ///   - PIN (if provided) is 4-6 digits
  Future<UserOperationResult> createUser({
    required String username,
    required String password,
    required String fullName,
    required UserRole role,
    String? pin,
    String? colorPreference,
  }) async {
    if (!_sessionManager.hasPermission('manage_users')) {
      throw AuthorizationException('manage_users');
    }

    final trimmedUsername = username.trim();
    final trimmedFullName = fullName.trim();

    if (trimmedUsername.isEmpty) {
      return UserOperationResult(success: false, message: 'Username is required');
    }
    if (trimmedFullName.isEmpty) {
      return UserOperationResult(success: false, message: 'Full name is required');
    }
    final passwordError = _validatePasswordComplexity(password);
    if (passwordError != null) {
      return UserOperationResult(success: false, message: passwordError);
    }
    if (pin != null && pin.isNotEmpty) {
      final pinRegex = RegExp(r'^\d{4,6}$');
      if (!pinRegex.hasMatch(pin)) {
        return UserOperationResult(
          success: false,
          message: 'PIN must be 4-6 digits',
        );
      }
    }

    // Check username uniqueness among non-deleted users.
    final existing = await _userRepository.getByUsername(trimmedUsername);
    if (existing != null) {
      return UserOperationResult(success: false, message: 'Username already exists');
    }

    final passwordHash = SecurityHelper.hashPassword(password);
    final now = DateTime.now();

    final user = User(
      username: trimmedUsername,
      passwordHash: passwordHash,
      pin: (pin != null && pin.isNotEmpty) ? pin : null,
      role: role,
      fullName: trimmedFullName,
      colorPreference: colorPreference ?? 'green',
      createdAt: now,
      updatedAt: now,
    );

    final id = await _userRepository.insert(user);
    final createdUser = user.copyWith(id: id);

    await _activityLogService.logActivity(
      action: 'USER_CREATED',
      entity: 'user',
      entityId: id,
      details: 'Created user: $trimmedUsername (${role.displayName})',
    );

    return UserOperationResult(
      success: true,
      message: 'User created successfully',
      user: createdUser,
    );
  }

  // ───────────────────────────────────────────────
  //  UPDATE
  // ───────────────────────────────────────────────

  /// Updates an existing user's profile fields.
  ///
  /// Only the provided (non-null) fields are changed.  Username uniqueness
  /// is checked against all non-deleted users *excluding* the user being
  /// edited (so the user can keep their own username).
  Future<UserOperationResult> updateUser({
    required int userId,
    String? username,
    String? fullName,
    UserRole? role,
    String? pin,
    String? colorPreference,
    String? profileImagePath,
  }) async {
    if (!_sessionManager.hasPermission('edit_users')) {
      throw AuthorizationException('edit_users');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    final trimmedUsername = username?.trim();
    final trimmedFullName = fullName?.trim();

    if (trimmedUsername != null && trimmedUsername.isEmpty) {
      return UserOperationResult(success: false, message: 'Username cannot be empty');
    }
    if (trimmedFullName != null && trimmedFullName.isEmpty) {
      return UserOperationResult(success: false, message: 'Full name cannot be empty');
    }
    if (pin != null && pin.isNotEmpty) {
      final pinRegex = RegExp(r'^\d{4,6}$');
      if (!pinRegex.hasMatch(pin)) {
        return UserOperationResult(
          success: false,
          message: 'PIN must be 4-6 digits',
        );
      }
    }

    // Check username uniqueness if it's being changed.
    if (trimmedUsername != null && trimmedUsername != user.username) {
      final existing = await _userRepository.getByUsername(trimmedUsername);
      if (existing != null && existing.id != userId) {
        return UserOperationResult(
          success: false,
          message: 'Username already exists',
        );
      }
    }

    final updatedUser = user.copyWith(
      username: trimmedUsername ?? user.username,
      fullName: trimmedFullName ?? user.fullName,
      role: role ?? user.role,
      pin: (pin != null && pin.isNotEmpty) ? pin : user.pin,
      colorPreference: colorPreference ?? user.colorPreference,
      profileImagePath: profileImagePath ?? user.profileImagePath,
      updatedAt: DateTime.now(),
    );

    await _userRepository.update(updatedUser);

    // If the current user edited their own account, update the session.
    if (_sessionManager.currentUser?.id == userId) {
      _sessionManager.setCurrentUser(updatedUser);
    }

    await _activityLogService.logActivity(
      action: 'USER_UPDATED',
      entity: 'user',
      entityId: userId,
      details: 'Updated user: ${updatedUser.username}',
    );

    return UserOperationResult(
      success: true,
      message: 'User updated successfully',
      user: updatedUser,
    );
  }

  // ───────────────────────────────────────────────
  //  PASSWORD
  // ───────────────────────────────────────────────

  /// Changes a user's own password (requires the old password).
  /// Users can change their own password; only those with `reset_password`
  /// permission can change others'.
  Future<UserOperationResult> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    // Users can change their own password; only admins can reset others'.
    if (_sessionManager.currentUser?.id != userId &&
        !_sessionManager.hasPermission('reset_password')) {
      throw AuthorizationException('reset_password');
    }

    // When changing own password, old password must match.
    if (_sessionManager.currentUser?.id == userId) {
      if (!SecurityHelper.verifyPassword(oldPassword, user.passwordHash)) {
        return UserOperationResult(
          success: false,
          message: 'Current password is incorrect',
        );
      }
    }

    final complexityError = _validatePasswordComplexity(newPassword);
    if (complexityError != null) {
      return UserOperationResult(success: false, message: complexityError);
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(
      passwordHash: newPasswordHash,
      updatedAt: DateTime.now(),
    );
    await _userRepository.update(updatedUser);

    await _activityLogService.logActivity(
      action: 'PASSWORD_CHANGED',
      entity: 'user',
      entityId: userId,
      details: 'Password changed for user: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'Password changed successfully');
  }

  /// Resets a user's password (admin operation, no old password needed).
  Future<UserOperationResult> resetPassword({
    required int userId,
    required String newPassword,
  }) async {
    if (!_sessionManager.hasPermission('reset_password')) {
      throw AuthorizationException('reset_password');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    final resetComplexityError = _validatePasswordComplexity(newPassword);
    if (resetComplexityError != null) {
      return UserOperationResult(success: false, message: resetComplexityError);
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(
      passwordHash: newPasswordHash,
      updatedAt: DateTime.now(),
    );
    await _userRepository.update(updatedUser);

    await _activityLogService.logActivity(
      action: 'PASSWORD_RESET',
      entity: 'user',
      entityId: userId,
      details: 'Password reset for user: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'Password reset successfully');
  }

  // ───────────────────────────────────────────────
  //  ACTIVATE / DEACTIVATE
  // ───────────────────────────────────────────────

  /// Activates a user.
  Future<UserOperationResult> activateUser(int userId) async {
    if (!_sessionManager.hasPermission('toggle_user_active')) {
      throw AuthorizationException('toggle_user_active');
    }

    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    await _userRepository.toggleActive(userId, true);

    await _activityLogService.logActivity(
      action: 'USER_ACTIVATED',
      entity: 'user',
      entityId: userId,
      details: 'Activated user: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'User activated successfully');
  }

  /// Deactivates a user.
  ///
  /// Prevents self-deactivation to avoid locking the current admin out.
  Future<UserOperationResult> deactivateUser(int userId) async {
    if (!_sessionManager.hasPermission('toggle_user_active')) {
      throw AuthorizationException('toggle_user_active');
    }

    // Prevent self-deactivation.
    if (_sessionManager.currentUser?.id == userId) {
      return UserOperationResult(
        success: false,
        message: 'You cannot deactivate your own account',
      );
    }

    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    await _userRepository.toggleActive(userId, false);

    await _activityLogService.logActivity(
      action: 'USER_DEACTIVATED',
      entity: 'user',
      entityId: userId,
      details: 'Deactivated user: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'User deactivated successfully');
  }

  // ───────────────────────────────────────────────
  //  SOFT DELETE
  // ───────────────────────────────────────────────

  /// Soft-deletes a user (sets deleted_at).  The user appears in Trash.
  ///
  /// Prevents self-deletion.
  Future<UserOperationResult> softDeleteUser(int userId) async {
    if (!_sessionManager.hasPermission('delete_users')) {
      throw AuthorizationException('delete_users');
    }

    // Prevent self-deletion.
    if (_sessionManager.currentUser?.id == userId) {
      return UserOperationResult(
        success: false,
        message: 'You cannot delete your own account',
      );
    }

    final user = await _userRepository.getById(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    await _userRepository.softDelete(userId);

    await _activityLogService.logActivity(
      action: 'USER_SOFT_DELETED',
      entity: 'user',
      entityId: userId,
      details: 'Soft-deleted user: ${user.username}',
    );

    return UserOperationResult(
      success: true,
      message: 'User moved to trash',
    );
  }

  // ───────────────────────────────────────────────
  //  RESTORE
  // ───────────────────────────────────────────────

  /// Restores a soft-deleted user (clears deleted_at).
  ///
  /// Checks for username conflicts before restoring: if another non-deleted
  /// user now owns the same username, the restore is rejected.
  Future<UserOperationResult> restoreUser(int userId) async {
    if (!_sessionManager.hasPermission('restore_trash')) {
      throw AuthorizationException('restore_trash');
    }

    final user = await _userRepository.getByIdWithDeleted(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    if (user.deletedAt == null) {
      return UserOperationResult(
        success: false,
        message: 'User is not deleted',
      );
    }

    // Check username conflict: is there an active user with the same username?
    final existing = await _userRepository.getByUsername(user.username);
    if (existing != null && existing.id != userId) {
      return UserOperationResult(
        success: false,
        message: 'Username "${user.username}" is already in use by another user',
      );
    }

    await _userRepository.restore(userId);

    await _activityLogService.logActivity(
      action: 'USER_RESTORED',
      entity: 'user',
      entityId: userId,
      details: 'Restored user: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'User restored successfully');
  }

  // ───────────────────────────────────────────────
  //  PERMANENT DELETE
  // ───────────────────────────────────────────────

  /// Permanently deletes a user row.  This is irreversible.
  ///
  /// Only available for soft-deleted users (from Trash) and only by users
  /// with `delete_users` permission.
  Future<UserOperationResult> permanentlyDeleteUser(int userId) async {
    if (!_sessionManager.hasPermission('delete_users')) {
      throw AuthorizationException('delete_users');
    }

    final user = await _userRepository.getByIdWithDeleted(userId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'User not found');
    }

    if (user.deletedAt == null) {
      return UserOperationResult(
        success: false,
        message: 'User must be in trash before permanent deletion',
      );
    }

    await _userRepository.permanentlyDelete(userId);

    await _activityLogService.logActivity(
      action: 'USER_PERMANENTLY_DELETED',
      entity: 'user',
      entityId: userId,
      details: 'Permanently deleted user: ${user.username}',
    );

    return UserOperationResult(
      success: true,
      message: 'User permanently deleted',
    );
  }
}
