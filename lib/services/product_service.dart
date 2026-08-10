import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class ProductService {
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final AuthService _authService = AuthService();

  Future<List<Product>> getActiveProducts() async {
    if (!_authService.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.getActiveProducts();
  }

  Future<List<Product>> getLowStockProducts() async {
    if (!_authService.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.getLowStockProducts();
  }

  Future<List<Product>> searchProducts(String query) async {
    if (!_authService.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.searchProducts(query);
  }

  Future<Product?> getProductById(int id) async {
    if (!_authService.hasPermission('view_products')) {
      return null;
    }
    return _productRepository.getById(id);
  }

  Future<bool> createProduct(Product product) async {
    if (!_authService.hasPermission('manage_products')) {
      return false;
    }

    if (product.name.isEmpty) {
      return false;
    }

    if (product.price <= 0) {
      return false;
    }

    if (product.stock < 0) {
      return false;
    }

    if (product.minStock < 0) {
      return false;
    }

    if (product.categoryId != null) {
      final category = await _categoryRepository.getById(product.categoryId!);
      if (category == null) {
        return false;
      }
    }

    await _productRepository.insert(product);
    return true;
  }

  Future<bool> updateProduct(Product product) async {
    if (!_authService.hasPermission('manage_products')) {
      return false;
    }

    if (product.name.isEmpty) {
      return false;
    }

    if (product.price <= 0) {
      return false;
    }

    if (product.stock < 0) {
      return false;
    }

    if (product.minStock < 0) {
      return false;
    }

    if (product.categoryId != null) {
      final category = await _categoryRepository.getById(product.categoryId!);
      if (category == null) {
        return false;
      }
    }

    await _productRepository.update(product);
    return true;
  }

  Future<bool> deleteProduct(int id) async {
    if (!_authService.hasPermission('manage_products')) {
      return false;
    }

    await _productRepository.softDelete(id);
    return true;
  }

  Future<bool> restoreProduct(int id) async {
    if (!_authService.hasPermission('manage_products')) {
      return false;
    }

    await _productRepository.restore(id);
    return true;
  }
}
