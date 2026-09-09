import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:sqflite/sqflite.dart';

class ProductDao extends BaseDao<Product> {
  @override
  String get tableName => 'products';

  @override
  Product fromMap(Map<String, dynamic> map) => Product.fromMap(map);

  Future<Product?> getByName(String name, {DatabaseExecutor? txn}) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'name = ? AND deleted_at IS NULL',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<Product>> getByCategory(int categoryId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'category_id = ? AND deleted_at IS NULL',
      whereArgs: [categoryId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Product>> getActiveProducts() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'is_active = 1 AND deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Product>> getLowStockProducts() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'stock <= min_stock AND is_active = 1 AND deleted_at IS NULL',
      orderBy: 'stock ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Product>> searchProducts(String query) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: '(name LIKE ?) AND deleted_at IS NULL',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Number of sellable products per category (active, not deleted).
  /// Used by the Categories screen to show "N products" per row without
  /// loading full product objects.
  Future<Map<int, int>> getCountsByCategory() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT category_id AS cid, COUNT(*) AS c FROM products '
      'WHERE is_active = 1 AND deleted_at IS NULL AND category_id IS NOT NULL '
      'GROUP BY category_id',
    );
    return {
      for (final row in rows)
        (row['cid'] as int): (row['c'] as int),
    };
  }

  /// Stock summary for the Products screen stat strip. Computed at the
  /// SQL level so it reflects the whole catalog, not the current search
  /// results.
  Future<({int total, int lowStock, int outOfStock})> getStockSummary() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS total, '
      'SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END) AS out_of_stock, '
      'SUM(CASE WHEN stock > 0 AND stock <= min_stock THEN 1 ELSE 0 END) AS low_stock '
      'FROM products WHERE is_active = 1 AND deleted_at IS NULL',
    );
    final row = rows.first;
    return (
      total: (row['total'] as int?) ?? 0,
      lowStock: (row['low_stock'] as int?) ?? 0,
      outOfStock: (row['out_of_stock'] as int?) ?? 0,
    );
  }

  Future<void> updateStock(int productId, int newStock, {DatabaseExecutor? txn}) async {
    final executor = txn ?? await db;
    await executor.update(
      tableName,
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }
}
