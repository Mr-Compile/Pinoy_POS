import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';

class StockHistoryDao extends BaseDao<StockHistory> {
  @override
  String get tableName => 'stock_history';

  @override
  StockHistory fromMap(Map<String, dynamic> map) => StockHistory.fromMap(map);

  Future<List<StockHistory>> getByProductId(int productId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<StockHistory>> getByUserId(int userId, {int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<StockHistory>> getByDateRange(DateTime start, DateTime end) async {
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
