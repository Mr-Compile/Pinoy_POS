import 'package:pinoy_pos/data/dao/sale_item_dao.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:sqflite/sqflite.dart';

class SaleItemRepository {
  final SaleItemDao _saleItemDao = SaleItemDao();

  Future<int> insert(SaleItem saleItem, {DatabaseExecutor? txn}) => _saleItemDao.insert(saleItem, txn: txn);
  Future<int> update(SaleItem saleItem, {DatabaseExecutor? txn}) => _saleItemDao.update(saleItem, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) => _saleItemDao.delete(id, txn: txn);
  Future<SaleItem?> getById(int id, {DatabaseExecutor? txn}) => _saleItemDao.getById(id, txn: txn);
  Future<List<SaleItem>> getBySaleId(int saleId, {DatabaseExecutor? txn}) => _saleItemDao.getBySaleId(saleId, txn: txn);
  Future<List<SaleItem>> getByProductId(int productId) => _saleItemDao.getByProductId(productId);

  /// Analytics: top-selling products by total quantity sold. See
  /// [SaleItemDao.getTopProductsByQuantity] for parameter semantics.
  Future<List<Map<String, dynamic>>> getTopProductsByQuantity({
    int limit = 5,
    DateTime? since,
    int? userId,
  }) =>
      _saleItemDao.getTopProductsByQuantity(limit: limit, since: since, userId: userId);
}
