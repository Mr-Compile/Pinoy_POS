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

  Future<List<SaleItem>> getByProductId(int productId) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return maps.map((map) => SaleItem.fromMap(map)).toList();
  }
}
