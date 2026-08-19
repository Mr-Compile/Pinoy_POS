import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/notification.dart';
import 'package:sqflite/sqflite.dart';

class NotificationDao extends BaseDao<Notification> {
  @override
  String get tableName => 'notifications';

  @override
  Notification fromMap(Map<String, dynamic> map) => Notification.fromMap(map);

  Future<List<Notification>> getByUserId(int userId) async {
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

  Future<List<Notification>> getUnreadByUserId(int userId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ? AND is_read = 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<int> getUnreadCount(int userId) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT COUNT(*) as count
      FROM notifications
      WHERE user_id = ? AND is_read = 0
    ''', [userId]);
    
    return result.first['count'] as int? ?? 0;
  }

  /// Marks a single notification as read.
  ///
  /// The [userId] scope is enforced so that a user can only mark their own
  /// notifications as read. Without this, a user who knew another user's
  /// notification id could mutate it.
  Future<void> markAsRead(int id, int userId) async {
    final database = await db;
    await database.update(
      tableName,
      {
        'is_read': 1,
        'read_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> markAllAsRead(int userId) async {
    final database = await db;
    await database.update(
      tableName,
      {
        'is_read': 1,
        'read_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ? AND is_read = 0',
      whereArgs: [userId],
    );
  }

  /// Checks whether an unread notification matching all of [type],
  /// [title], and [message] already exists for [userId].
  ///
  /// Used for low-stock deduplication so that repeated stock adjustments
  /// on a product that is already below its threshold do not spam the
  /// user with identical notifications.
  Future<bool> hasUnreadNotification({
    required int userId,
    required String type,
    required String title,
    required String message,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final result = await executor.rawQuery(
      '''
        SELECT COUNT(*) AS count
        FROM notifications
        WHERE user_id = ?
          AND is_read = 0
          AND type = ?
          AND title = ?
          AND message = ?
      ''',
      [userId, type, title, message],
    );
    return (result.first['count'] as int? ?? 0) > 0;
  }
}
