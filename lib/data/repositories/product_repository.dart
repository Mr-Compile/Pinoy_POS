import 'package:pinoy_pos/data/dao/product_dao.dart';
import 'package:pinoy_pos/data/models/product.dart';

class ProductRepository {
  final ProductDao _productDao = ProductDao();

  Future<int> insert(Product product) => _productDao.insert(product);
  Future<int> update(Product product) => _productDao.update(product);
  Future<int> delete(int id) => _productDao.delete(id);
  Future<int> softDelete(int id) => _productDao.softDelete(id);
  Future<int> restore(int id) => _productDao.restore(id);
  Future<Product?> getById(int id) => _productDao.getById(id);
  Future<List<Product>> getAll() => _productDao.getAll();
  Future<List<Product>> getAllActive() => _productDao.getAllActive();
  Future<List<Product>> getDeleted() => _productDao.getDeleted();
  Future<Product?> getByBarcode(String barcode) => _productDao.getByBarcode(barcode);
  Future<List<Product>> getByCategory(int categoryId) => _productDao.getByCategory(categoryId);
  Future<List<Product>> getActiveProducts() => _productDao.getActiveProducts();
  Future<List<Product>> getLowStockProducts() => _productDao.getLowStockProducts();
  Future<List<Product>> searchProducts(String query) => _productDao.searchProducts(query);
  Future<void> updateStock(int productId, int newStock) => _productDao.updateStock(productId, newStock);
}
