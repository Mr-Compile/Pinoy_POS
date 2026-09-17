import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/ai_chat_message.dart';
import 'package:sqflite/sqflite.dart';

/// Persistence for per-user AI advisor conversation history.
///
/// Rows are keyed by `user_id` so multiple accounts on the same device
/// never see each other's conversations. Ordering uses the row `id`
/// (insertion order), which is more reliable than `created_at` when
/// several messages land within the same millisecond.
class AIChatMessageDao extends BaseDao<AIChatMessage> {
  @override
  String get tableName => 'ai_chat_messages';

  @override
  AIChatMessage fromMap(Map<String, dynamic> map) =>
      AIChatMessage.fromRow(map);

  Future<int> insertForUser(
    int userId,
    AIChatMessage message, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    return executor.insert(tableName, message.toRow(userId));
  }

  /// The newest [limit] messages for [userId], returned oldest → newest
  /// so the caller can render them directly.
  Future<List<AIChatMessage>> getRecentForUser(
    int userId, {
    int limit = 200,
  }) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return maps.reversed.map(fromMap).toList();
  }

  /// Deletes the entire stored conversation for [userId]. Only invoked
  /// when the user explicitly starts a new conversation.
  Future<int> deleteForUser(int userId) async {
    final database = await db;
    return database.delete(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Keeps only the newest [keep] messages for [userId], bounding table
  /// growth over long-running installations.
  Future<int> pruneForUser(int userId, {int keep = 200}) async {
    final database = await db;
    return database.rawDelete(
      'DELETE FROM ai_chat_messages WHERE user_id = ? AND id NOT IN ('
      'SELECT id FROM ai_chat_messages WHERE user_id = ? '
      'ORDER BY id DESC LIMIT ?)',
      [userId, userId, keep],
    );
  }
}
