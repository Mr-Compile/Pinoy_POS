import 'package:pinoy_pos/data/dao/sale_item_dao.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';

class SaleItemRepository {
  final SaleItemDao _saleItemDao = SaleItemDao();

  Future<int> insert(SaleItem saleItem) => _saleItemDao.insert(saleItem);
  Future<int> update(SaleItem saleItem) => _saleItemDao.update(saleItem);
  Future<int> delete(int id) => _saleItemDao.delete(id);
  Future<SaleItem?> getById(int id) => _saleItemDao.getById(id);
  Future<List<SaleItem>> getAll() => _saleItemDao.getAll();
  Future<List<SaleItem>> getBySaleId(int saleId) => _saleItemDao.getBySaleId(saleId);
  Future<List<SaleItem>> getByProductId(int productId) => _saleItemDao.getByProductId(productId);
}
