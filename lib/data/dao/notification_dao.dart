import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/notification.dart';

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

  Future<void> markAsRead(int id) async {
    final database = await db;
    await database.update(
      tableName,
      {
        'is_read': 1,
        'read_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
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
}
