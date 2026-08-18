import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';

class ProductService {
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();

  Future<List<Product>> getActiveProducts() async {
    if (!_sessionManager.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.getActiveProducts();
  }

  Future<List<Product>> getDeletedProducts() async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    return _productRepository.getDeleted();
  }

  Future<List<Product>> getLowStockProducts() async {
    if (!_sessionManager.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.getLowStockProducts();
  }

  Future<List<Product>> searchProducts(String query) async {
    if (!_sessionManager.hasPermission('view_products')) {
      return [];
    }
    return _productRepository.searchProducts(query);
  }

  Future<Product?> getProductById(int id) async {
    if (!_sessionManager.hasPermission('view_products')) {
      return null;
    }
    return _productRepository.getById(id);
  }

  Future<bool> createProduct(Product product) async {
    if (!_sessionManager.hasPermission('edit_products')) {
      throw AuthorizationException('edit_products');
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
    await _activityLogService.logActivity(
      action: 'create_product',
      entity: 'product',
      details: 'Created product: ${product.name}',
    );
    return true;
  }

  Future<bool> updateProduct(Product product) async {
    if (!_sessionManager.hasPermission('edit_products')) {
      throw AuthorizationException('edit_products');
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
    await _activityLogService.logActivity(
      action: 'update_product',
      entity: 'product',
      entityId: product.id,
      details: 'Updated product: ${product.name}',
    );
    return true;
  }

  Future<bool> deleteProduct(int id) async {
    if (!_sessionManager.hasPermission('delete_products')) {
      throw AuthorizationException('delete_products');
    }

    await _productRepository.softDelete(id);
    await _activityLogService.logActivity(
      action: 'delete_product',
      entity: 'product',
      entityId: id,
      details: 'Soft-deleted product',
    );
    return true;
  }

  Future<bool> restoreProduct(int id) async {
    if (!_sessionManager.hasPermission('delete_products')) {
      throw AuthorizationException('delete_products');
    }

    await _productRepository.restore(id);
    await _activityLogService.logActivity(
      action: 'restore_product',
      entity: 'product',
      entityId: id,
      details: 'Restored product from trash',
    );
    return true;
  }

  /// Permanently deletes a product row from the database.
  /// This is irreversible and should only be called from the Trash system
  /// for products that have already been soft-deleted.
  Future<bool> permanentlyDeleteProduct(int id) async {
    if (!_sessionManager.hasPermission('delete_products')) {
      throw AuthorizationException('delete_products');
    }

    await _productRepository.delete(id);
    await _activityLogService.logActivity(
      action: 'permanently_delete_product',
      entity: 'product',
      entityId: id,
      details: 'Permanently deleted product',
    );
    return true;
  }
}
