import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/ai_usage.dart';

class AIUsageDao extends BaseDao<AIUsage> {
  @override
  String get tableName => 'ai_usage';

  @override
  AIUsage fromMap(Map<String, dynamic> map) => AIUsage.fromMap(map);

  Future<List<AIUsage>> getByUserId(int userId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<int> getTodayCount(int userId) async {
    final database = await db;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final result = await database.rawQuery('''
      SELECT COUNT(*) as count
      FROM ai_usage
      WHERE user_id = ? AND created_at >= ? AND created_at < ?
    ''', [userId, startOfDay.toIso8601String(), endOfDay.toIso8601String()]);
    
    return result.first['count'] as int? ?? 0;
  }
}
