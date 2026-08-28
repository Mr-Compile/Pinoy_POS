import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:sqflite/sqflite.dart';

class AIQuotaDao extends BaseDao<AIQuota> {
  @override
  String get tableName => 'ai_quota';

  @override
  AIQuota fromMap(Map<String, dynamic> map) => AIQuota.fromMap(map);

  Future<AIQuota?> getByUserId(int userId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<AIQuota>> getForActiveUsers({DatabaseExecutor? txn}) async {
    final executor = txn ?? await db;
    final maps = await executor.rawQuery('''
      SELECT q.*
      FROM ai_quota q
      INNER JOIN users u ON u.id = q.user_id
      WHERE u.deleted_at IS NULL
    ''');
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<void> updateByUserId(
    int userId, {
    required Map<String, dynamic> values,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      values,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> resetDailyUsage(
    int userId, {
    required DateTime quotaDate,
    required DateTime lastResetAt,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      {
        'daily_usage': 0,
        'quota_date': quotaDate.toIso8601String(),
        'last_reset_at': lastResetAt.toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> resetAllDailyUsage({
    required DateTime quotaDate,
    required DateTime lastResetAt,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      {
        'daily_usage': 0,
        'quota_date': quotaDate.toIso8601String(),
        'last_reset_at': lastResetAt.toIso8601String(),
      },
    );
  }

  Future<void> updateDailyUsage(
    int userId,
    int dailyUsage, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      {'daily_usage': dailyUsage},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updateDailyQuota(
    int userId,
    int dailyQuota, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      {'daily_quota': dailyQuota},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
