import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';

/// Activity log service.
///
/// Reads the current user from [SessionManager] instead of instantiating
/// [AuthService]. This breaks the previous circular dependency:
///
///     AuthService -> ActivityLogService -> AuthService -> ... (Stack Overflow)
class ActivityLogService {
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final SessionManager _sessionManager = SessionManager();

  Future<List<ActivityLog>> getRecentActivities() async {
    return _activityLogRepository.getRecentActivities();
  }

  Future<List<ActivityLog>> getUserActivities(int userId) async {
    return _activityLogRepository.getByUserId(userId);
  }

  Future<void> logActivity({
    required String action,
    String? entity,
    int? entityId,
    String? details,
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
    await _activityLogRepository.insert(activityLog);
  }
}
