import 'package:pinoy_pos/data/dao/ai_chat_message_dao.dart';
import 'package:pinoy_pos/data/models/ai_chat_message.dart';
import 'package:sqflite/sqflite.dart';

class AIChatMessageRepository {
  final AIChatMessageDao _dao = AIChatMessageDao();

  Future<int> insertForUser(
    int userId,
    AIChatMessage message, {
    DatabaseExecutor? txn,
  }) =>
      _dao.insertForUser(userId, message, txn: txn);

  Future<List<AIChatMessage>> getRecentForUser(
    int userId, {
    int limit = 200,
  }) =>
      _dao.getRecentForUser(userId, limit: limit);

  Future<int> deleteForUser(int userId) => _dao.deleteForUser(userId);

  Future<int> pruneForUser(int userId, {int keep = 200}) =>
      _dao.pruneForUser(userId, keep: keep);
}
