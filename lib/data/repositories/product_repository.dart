import 'package:pinoy_pos/data/dao/product_dao.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:sqflite/sqflite.dart';

class ProductRepository {
  final ProductDao _productDao = ProductDao();

  Future<int> insert(Product product, {DatabaseExecutor? txn}) => _productDao.insert(product, txn: txn);
  Future<int> update(Product product, {DatabaseExecutor? txn}) => _productDao.update(product, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) => _productDao.delete(id, txn: txn);
  Future<int> softDelete(int id, {DatabaseExecutor? txn}) => _productDao.softDelete(id, txn: txn);
  Future<int> restore(int id, {DatabaseExecutor? txn}) => _productDao.restore(id, txn: txn);
  Future<Product?> getById(int id, {DatabaseExecutor? txn}) => _productDao.getById(id, txn: txn);
  Future<Product?> getByName(String name, {DatabaseExecutor? txn}) => _productDao.getByName(name, txn: txn);
  Future<List<Product>> getAll() => _productDao.getAll();
  Future<List<Product>> getAllActive() => _productDao.getAllActive();
  Future<List<Product>> getDeleted() => _productDao.getDeleted();
  Future<List<Product>> getByCategory(int categoryId) => _productDao.getByCategory(categoryId);
  Future<List<Product>> getActiveProducts() => _productDao.getActiveProducts();
  Future<List<Product>> getLowStockProducts() => _productDao.getLowStockProducts();
  Future<List<Product>> searchProducts(String query) => _productDao.searchProducts(query);
  Future<void> updateStock(int productId, int newStock, {DatabaseExecutor? txn}) => _productDao.updateStock(productId, newStock, txn: txn);
}
