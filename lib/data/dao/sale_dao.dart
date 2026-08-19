import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/sale.dart';

class SaleDao extends BaseDao<Sale> {
  @override
  String get tableName => 'sales';

  @override
  Sale fromMap(Map<String, dynamic> map) => Sale.fromMap(map);

  Future<List<Sale>> getByUserId(int userId, {int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Sale>> getByDateRange(DateTime start, DateTime end, {int limit = 500}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'created_at BETWEEN ? AND ? AND deleted_at IS NULL',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Sale>> getByDateRangeAndUser(
    DateTime start,
    DateTime end,
    int userId, {
    int limit = 200,
  }) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'created_at BETWEEN ? AND ? AND user_id = ? AND deleted_at IS NULL',
      whereArgs: [start.toIso8601String(), end.toIso8601String(), userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<double> getTotalSalesForDate(DateTime date) async {
    final database = await db;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    
    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND deleted_at IS NULL
    ''', [start.toIso8601String(), end.toIso8601String()]);
    
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForMonth(int year, int month) async {
    final database = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    
    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND deleted_at IS NULL
    ''', [start.toIso8601String(), end.toIso8601String()]);
    
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForUser(int userId) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE user_id = ? AND deleted_at IS NULL
    ''', [userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForDateForUser(DateTime date, int userId) async {
    final database = await db;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND user_id = ? AND deleted_at IS NULL
    ''', [start.toIso8601String(), end.toIso8601String(), userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForMonthForUser(int year, int month, int userId) async {
    final database = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND user_id = ? AND deleted_at IS NULL
    ''', [start.toIso8601String(), end.toIso8601String(), userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
