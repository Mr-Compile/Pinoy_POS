import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/product.dart';

class ProductDao extends BaseDao<Product> {
  @override
  String get tableName => 'products';

  @override
  Product fromMap(Map<String, dynamic> map) => Product.fromMap(map);

  Future<Product?> getByBarcode(String barcode) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'barcode = ? AND deleted_at IS NULL',
      whereArgs: [barcode],
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
      where: '(name LIKE ? OR barcode LIKE ?) AND deleted_at IS NULL',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<void> updateStock(int productId, int newStock) async {
    final database = await db;
    await database.update(
      tableName,
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }
}
