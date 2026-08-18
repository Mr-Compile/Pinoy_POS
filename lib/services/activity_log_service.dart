import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:sqflite/sqflite.dart';

/// Activity log service.
///
/// Reads the current user from [SessionManager] instead of instantiating
/// [AuthService]. This breaks the previous circular dependency:
///
///     AuthService -> ActivityLogService -> AuthService -> ... (Stack Overflow)
class ActivityLogService {
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final SessionManager _sessionManager = SessionManager();

  /// Returns recent activities scoped to the current user's role.
  ///
  /// - Owner / Admin: all activities (database-level, no UI filtering).
  /// - Staff: only the current user's own activities (WHERE user_id = ?).
  Future<List<ActivityLog>> getRecentActivities() async {
    if (!_sessionManager.hasPermission('view_activity_logs')) {
      return [];
    }
    final currentUser = _sessionManager.currentUser;
    if (currentUser == null) {
      return [];
    }
    // Staff may only view their own activity logs. The filter is applied
    // at the DAO/query level, not in the UI.
    if (currentUser.role == UserRole.staff) {
      return _activityLogRepository.getByUserId(currentUser.id!);
    }
    return _activityLogRepository.getRecentActivities();
  }

  Future<List<ActivityLog>> getUserActivities(int userId) async {
    if (!_sessionManager.hasPermission('view_activity_logs')) {
      return [];
    }
    // Staff may only request their own activities.
    final currentUser = _sessionManager.currentUser;
    if (currentUser == null) {
      return [];
    }
    if (currentUser.role == UserRole.staff && currentUser.id != userId) {
      return [];
    }
    return _activityLogRepository.getByUserId(userId);
  }

  Future<void> logActivity({
    required String action,
    String? entity,
    int? entityId,
    String? details,
    DatabaseExecutor? txn,
  }) async {
    final currentUser = _sessionManager.currentUser;
    final activityLog = ActivityLog(
      userId: currentUser?.id ?? 0,
      role: currentUser?.role.name,
      action: action,
      entity: entity,
      entityId: entityId,
      details: details,
      createdAt: DateTime.now(),
    );
    await _activityLogRepository.insert(activityLog, txn: txn);
  }
}
