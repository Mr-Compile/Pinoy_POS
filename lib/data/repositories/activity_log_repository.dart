import 'package:pinoy_pos/data/dao/activity_log_dao.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:sqflite/sqflite.dart';

class ActivityLogRepository {
  final ActivityLogDao _activityLogDao = ActivityLogDao();

  Future<int> insert(ActivityLog activityLog, {DatabaseExecutor? txn}) => _activityLogDao.insert(activityLog, txn: txn);
  Future<int> update(ActivityLog activityLog) => _activityLogDao.update(activityLog);
  Future<int> delete(int id) => _activityLogDao.delete(id);
  Future<ActivityLog?> getById(int id) => _activityLogDao.getById(id);
  Future<List<ActivityLog>> getAll() => _activityLogDao.getAll();
  Future<List<ActivityLog>> getByUserId(int userId) => _activityLogDao.getByUserId(userId);
  Future<List<ActivityLog>> getByEntity(String entity, int entityId) => _activityLogDao.getByEntity(entity, entityId);
  Future<List<ActivityLog>> getRecentActivities({int limit = 50}) => _activityLogDao.getRecentActivities(limit: limit);
  Future<List<ActivityLog>> getByDateRange(DateTime start, DateTime end, {int limit = 500}) => _activityLogDao.getByDateRange(start, end, limit: limit);
}
