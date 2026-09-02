import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:sqflite/sqflite.dart';

class SaleItemDao extends BaseDao<SaleItem> {
  @override
  String get tableName => 'sale_items';

  @override
  SaleItem fromMap(Map<String, dynamic> map) => SaleItem.fromMap(map);

  Future<List<SaleItem>> getBySaleId(int saleId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    return maps.map((map) => SaleItem.fromMap(map)).toList();
  }

  /// Returns all sale items belonging to any of the given [saleIds].
  Future<List<SaleItem>> getBySaleIds(List<int> saleIds, {DatabaseExecutor? txn}) async {
    if (saleIds.isEmpty) return [];

    final executor = txn ?? await db;
    final placeholders = List.filled(saleIds.length, '?').join(', ');
    final maps = await executor.query(
      tableName,
      where: 'sale_id IN ($placeholders)',
      whereArgs: saleIds,
      orderBy: 'sale_id, id',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<SaleItem>> getByProductId(int productId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return maps.map((map) => SaleItem.fromMap(map)).toList();
  }

  /// Returns the top-selling products for confirmed, non-voided sales.
  ///
  /// Parameters:
  /// - [limit]: maximum number of rows to return.
  /// - [since]: optional inclusive lower bound on `sales.created_at`.
  /// - [until]: optional exclusive upper bound on `sales.created_at`.
  ///   When null, all future dates are allowed (effectively now).
  /// - [userId]: optional filter restricting to sales made by [userId].
  ///   Used for Staff dashboards so a Staff member only sees their own
  ///   top products.  When null, all users' sales are aggregated.
  /// - [sortByRevenue]: when true, order by revenue desc; otherwise by qty.
  ///
  /// Returns a list of maps with keys:
  ///   `product_id`, `product_name`, `total_quantity`, `revenue`.
  Future<List<Map<String, dynamic>>> getTopProducts({
    int limit = 5,
    DateTime? since,
    DateTime? until,
    int? userId,
    bool sortByRevenue = false,
  }) async {
    final database = await db;
    final args = <Object?>[];
    final conditions = <String>[
      's.deleted_at IS NULL',
      "s.payment_status = 'confirmed'",
    ];

    if (since != null) {
      conditions.add('s.created_at >= ?');
      args.add(since.toIso8601String());
    }
    if (until != null) {
      conditions.add('s.created_at < ?');
      args.add(until.toIso8601String());
    }
    if (userId != null) {
      conditions.add('s.user_id = ?');
      args.add(userId);
    }
    args.add(limit);

    final orderBy = sortByRevenue
        ? 'COALESCE(SUM(si.total_price), 0) DESC'
        : 'SUM(si.quantity) DESC';

    return database.rawQuery('''
      SELECT si.product_id AS product_id,
             COALESCE(si.product_name, p.name, 'Product #' || si.product_id) AS product_name,
             SUM(si.quantity) AS total_quantity,
             COALESCE(SUM(si.total_price), 0) AS revenue
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      LEFT JOIN products p ON si.product_id = p.id
      WHERE ${conditions.join(' AND ')}
      GROUP BY si.product_id, COALESCE(si.product_name, p.name, 'Product #' || si.product_id)
      ORDER BY $orderBy
      LIMIT ?
    ''', args);
  }
}
