import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';

class ActivityLogDao extends BaseDao<ActivityLog> {
  @override
  String get tableName => 'activity_logs';

  @override
  ActivityLog fromMap(Map<String, dynamic> map) => ActivityLog.fromMap(map);

  Future<List<ActivityLog>> getByUserId(int userId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: 100,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<ActivityLog>> getRecentActivities({int limit = 50}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<ActivityLog>> getByDateRange(DateTime start, DateTime end) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
