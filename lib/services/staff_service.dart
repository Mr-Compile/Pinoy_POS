import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/ai_quota_service.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:pinoy_pos/services/user_service.dart';

/// Sort order for the staff management list.
enum StaffSortOrder {
  nameAsc,
  nameDesc,
  usernameAsc,
  usernameDesc,
  createdAtAsc,
  createdAtDesc,
}

/// Service for owner staff management.
///
/// Enforces the `manage_staff` permission and restricts every operation to
/// accounts with [UserRole.staff].  Sales analytics are delegated to
/// [SalesAnalyticsService] so the staff detail screen reuses the same
/// reporting engine as the rest of the app.
class StaffService {
  final UserRepository _userRepository = UserRepository();
  final SaleRepository _saleRepository = SaleRepository();
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final ActivityLogService _activityLogService = ActivityLogService();
  final SalesAnalyticsService _salesAnalyticsService = SalesAnalyticsService();
  final SessionManager _sessionManager = SessionManager();
  final TrashService _trashService = TrashService();

  User? get currentUser => _sessionManager.currentUser;

  void _assertPermission() {
    if (!_sessionManager.hasPermission('manage_staff')) {
      throw AuthorizationException('manage_staff');
    }
  }

  User? _validateStaffUser(User? user) {
    if (user == null) return null;
    if (user.role != UserRole.staff) return null;
    if (user.deletedAt != null) return null;
    return user;
  }

  // ───────────────────────────────────────────────
  //  READ
  // ───────────────────────────────────────────────

  /// Returns non-deleted staff accounts, optionally filtered, sorted and
  /// searched by the caller.
  Future<List<User>> getStaff({
    String? search,
    StaffSortOrder sortBy = StaffSortOrder.nameAsc,
    bool? activeOnly,
  }) async {
    _assertPermission();

    var staff = await _userRepository.getByRole(UserRole.staff);

    if (activeOnly == true) {
      staff = staff.where((u) => u.isActive).toList();
    } else if (activeOnly == false) {
      staff = staff.where((u) => !u.isActive).toList();
    }

    if (search != null && search.trim().isNotEmpty) {
      final query = search.trim().toLowerCase();
      staff = staff.where((u) {
        return u.username.toLowerCase().contains(query) ||
            u.fullName.toLowerCase().contains(query);
      }).toList();
    }

    staff = _sortStaff(staff, sortBy);
    return staff;
  }

  /// Returns a single non-deleted staff member by id.
  Future<User?> getStaffById(int id) async {
    _assertPermission();
    final user = await _userRepository.getById(id);
    return _validateStaffUser(user);
  }

  /// Returns all soft-deleted staff accounts.
  Future<List<User>> getDeletedStaff() async {
    _assertPermission();
    final deleted = await _userRepository.getDeleted();
    return deleted.where((u) => u.role == UserRole.staff).toList();
  }

  List<User> _sortStaff(List<User> staff, StaffSortOrder sortBy) {
    switch (sortBy) {
      case StaffSortOrder.nameAsc:
        staff.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      case StaffSortOrder.nameDesc:
        staff.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()));
      case StaffSortOrder.usernameAsc:
        staff.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
      case StaffSortOrder.usernameDesc:
        staff.sort((a, b) => b.username.toLowerCase().compareTo(a.username.toLowerCase()));
      case StaffSortOrder.createdAtAsc:
        staff.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case StaffSortOrder.createdAtDesc:
        staff.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return staff;
  }

  // ───────────────────────────────────────────────
  //  CREATE
  // ───────────────────────────────────────────────

  /// Creates a new staff account with a default temporary password.
  Future<UserOperationResult> createStaff({
    required String username,
    required String fullName,
    String? pin,
  }) async {
    _assertPermission();

    final trimmedUsername = username.trim();
    final trimmedFullName = fullName.trim();

    if (trimmedUsername.isEmpty) {
      return UserOperationResult(success: false, message: 'Username is required');
    }
    if (trimmedFullName.isEmpty) {
      return UserOperationResult(success: false, message: 'Full name is required');
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

    final existing = await _userRepository.getByUsername(trimmedUsername);
    if (existing != null) {
      return UserOperationResult(success: false, message: 'Username already exists');
    }

    final passwordHash =
        SecurityHelper.hashPassword(AppConstants.defaultTemporaryPassword);
    final now = DateTime.now();

    final staff = User(
      username: trimmedUsername,
      passwordHash: passwordHash,
      pin: (pin != null && pin.isNotEmpty) ? SecurityHelper.hashPin(pin) : null,
      pinLength: (pin != null && pin.isNotEmpty) ? pin.length : null,
      role: UserRole.staff,
      fullName: trimmedFullName,
      mustChangePassword: true,
      createdAt: now,
      updatedAt: now,
    );

    final id = await _userRepository.insert(staff);
    final createdStaff = staff.copyWith(id: id);

    await AIQuotaService().ensureQuotaForUser(id);

    await _activityLogService.logActivity(
      action: 'STAFF_CREATED',
      entity: 'user',
      entityId: id,
      details: 'Created staff: $trimmedUsername',
    );

    return UserOperationResult(
      success: true,
      message: 'Staff created successfully',
      user: createdStaff,
    );
  }

  // ───────────────────────────────────────────────
  //  UPDATE
  // ───────────────────────────────────────────────

  /// Updates a staff member's profile.  The role cannot be changed through
  /// this flow — staff always remain staff.
  Future<UserOperationResult> updateStaff({
    required int staffId,
    String? username,
    String? fullName,
    String? pin,
    String? profileImagePath,
  }) async {
    _assertPermission();

    final user = await _userRepository.getById(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
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

    if (trimmedUsername != null && trimmedUsername != user.username) {
      final existing = await _userRepository.getByUsername(trimmedUsername);
      if (existing != null && existing.id != staffId) {
        return UserOperationResult(
          success: false,
          message: 'Username already exists',
        );
      }
    }

    String? newPin;
    int? newPinLength;
    if (pin == null) {
      newPin = user.pin;
      newPinLength = user.pinLength;
    } else if (pin.isEmpty) {
      newPin = null;
      newPinLength = null;
    } else {
      newPin = SecurityHelper.hashPin(pin);
      newPinLength = pin.length;
    }

    final updated = user.copyWith(
      username: trimmedUsername ?? user.username,
      fullName: trimmedFullName ?? user.fullName,
      pin: newPin,
      pinLength: newPinLength,
      profileImagePath: profileImagePath ?? user.profileImagePath,
      updatedAt: DateTime.now(),
    );

    await _userRepository.update(updated);

    await _activityLogService.logActivity(
      action: 'STAFF_UPDATED',
      entity: 'user',
      entityId: staffId,
      details: 'Updated staff: ${updated.username}',
    );

    return UserOperationResult(
      success: true,
      message: 'Staff updated successfully',
      user: updated,
    );
  }

  // ───────────────────────────────────────────────
  //  PASSWORD
  // ───────────────────────────────────────────────

  /// Resets a staff member's password to the default temporary password.
  Future<UserOperationResult> resetStaffPassword(int staffId) async {
    _assertPermission();

    final user = await _userRepository.getById(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }

    final newPasswordHash =
        SecurityHelper.hashPassword(AppConstants.defaultTemporaryPassword);
    final updated = user.copyWith(
      passwordHash: newPasswordHash,
      mustChangePassword: true,
      updatedAt: DateTime.now(),
    );
    await _userRepository.update(updated);

    await _activityLogService.logActivity(
      action: 'STAFF_PASSWORD_RESET',
      entity: 'user',
      entityId: staffId,
      details: 'Password reset for staff: ${user.username}',
    );

    return UserOperationResult(
      success: true,
      message: 'Password reset successfully. The staff member will need to change it on next login.',
    );
  }

  // ───────────────────────────────────────────────
  //  ACTIVATE / DEACTIVATE
  // ───────────────────────────────────────────────

  /// Activates a staff account.
  Future<UserOperationResult> activateStaff(int staffId) async {
    _assertPermission();

    final user = await _userRepository.getById(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }

    await _userRepository.toggleActive(staffId, true);

    await _activityLogService.logActivity(
      action: 'STAFF_ACTIVATED',
      entity: 'user',
      entityId: staffId,
      details: 'Activated staff: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'Staff activated successfully');
  }

  /// Deactivates a staff account.  Prevents self-deactivation.
  Future<UserOperationResult> deactivateStaff(int staffId) async {
    _assertPermission();

    if (_sessionManager.currentUser?.id == staffId) {
      return UserOperationResult(
        success: false,
        message: 'You cannot deactivate your own account',
      );
    }

    final user = await _userRepository.getById(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }

    await _userRepository.toggleActive(staffId, false);

    await _activityLogService.logActivity(
      action: 'STAFF_DEACTIVATED',
      entity: 'user',
      entityId: staffId,
      details: 'Deactivated staff: ${user.username}',
    );

    return UserOperationResult(success: true, message: 'Staff deactivated successfully');
  }

  // ───────────────────────────────────────────────
  //  DELETE
  // ───────────────────────────────────────────────

  /// Soft-deletes a staff account.
  Future<UserOperationResult> softDeleteStaff(int staffId) async {
    _assertPermission();

    if (_sessionManager.currentUser?.id == staffId) {
      return UserOperationResult(
        success: false,
        message: 'You cannot delete your own account',
      );
    }

    final user = await _userRepository.getById(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }

    final result = await _trashService.moveToTrash(
      entityType: 'user',
      entityId: staffId,
      entityName: user.fullName,
      snapshotJson: TrashService.snapshotForUser(user),
    );

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'STAFF_SOFT_DELETED',
        entity: 'user',
        entityId: staffId,
        details: 'Soft-deleted staff: ${user.username}',
      );

      return UserOperationResult(
        success: true,
        message: 'Staff moved to trash',
      );
    }

    return UserOperationResult(
      success: false,
      message: result.message,
    );
  }

  /// Restores a soft-deleted staff account.
  Future<UserOperationResult> restoreStaff(int staffId) async {
    _assertPermission();

    final user = await _userRepository.getByIdWithDeleted(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }
    if (user.deletedAt == null) {
      return UserOperationResult(success: false, message: 'Staff is not deleted');
    }

    final result = await _trashService.restoreByEntity('user', staffId);

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'STAFF_RESTORED',
        entity: 'user',
        entityId: staffId,
        details: 'Restored staff: ${user.username}',
      );

      return UserOperationResult(
          success: true, message: 'Staff restored successfully');
    }

    return UserOperationResult(
      success: false,
      message: result.message,
    );
  }

  /// Permanently deletes a staff account.
  Future<UserOperationResult> permanentlyDeleteStaff(int staffId) async {
    _assertPermission();

    final user = await _userRepository.getByIdWithDeleted(staffId);
    if (user == null) {
      return UserOperationResult(success: false, message: 'Staff not found');
    }
    if (user.role != UserRole.staff) {
      return UserOperationResult(success: false, message: 'User is not a staff member');
    }
    if (user.deletedAt == null) {
      return UserOperationResult(
        success: false,
        message: 'Staff must be in trash before permanent deletion',
      );
    }

    final result = await _trashService.permanentDeleteByEntity('user', staffId);

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'STAFF_PERMANENTLY_DELETED',
        entity: 'user',
        entityId: staffId,
        details: 'Permanently deleted staff: ${user.username}',
      );

      return UserOperationResult(
        success: true,
        message: 'Staff permanently deleted',
      );
    }

    return UserOperationResult(
      success: false,
      message: result.message,
    );
  }

  // ───────────────────────────────────────────────
  //  SALES & ACTIVITY
  // ───────────────────────────────────────────────

  /// Returns confirmed sales analytics for a staff member over the selected
  /// [period].
  Future<SalesAnalytics> getStaffSalesAnalytics(
    int staffUserId,
    ReportingPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    _assertPermission();
    return _salesAnalyticsService.getStaffDetailAnalytics(
      staffUserId,
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
  }

  /// Returns the most recent sales for a staff member, newest first.
  Future<List<Sale>> getStaffRecentSales(
    int staffUserId, {
    int limit = 50,
  }) async {
    _assertPermission();
    return _saleRepository.getByUserId(staffUserId, limit: limit);
  }

  /// Returns the staff member's own activity logs and any account-level
  /// events (creation, updates, status changes) related to that staff record.
  Future<List<ActivityLog>> getStaffActivityLogs(int staffUserId) async {
    _assertPermission();
    final ownLogs = await _activityLogRepository.getByUserId(staffUserId);
    final accountLogs =
        await _activityLogRepository.getByEntity('user', staffUserId);
    final combined = [...ownLogs, ...accountLogs];
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }
}
