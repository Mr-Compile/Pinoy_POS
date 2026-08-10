import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/repositories/activity_log_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class ActivityLogService {
  final ActivityLogRepository _activityLogRepository = ActivityLogRepository();
  final AuthService _authService = AuthService();

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
    final activityLog = ActivityLog(
      userId: _authService.currentUser?.id ?? 0,
      action: action,
      entity: entity,
      entityId: entityId,
      details: details,
      createdAt: DateTime.now(),
    );
    await _activityLogRepository.insert(activityLog);
  }
}
