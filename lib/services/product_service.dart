import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/attachment_service.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';

class ProductService {
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final ImageService _imageService = ImageService();
  final AttachmentService _attachmentService = AttachmentService();
  final TrashService _trashService = TrashService();

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

  Future<Product?> getProductByName(String name) async {
    if (!_sessionManager.hasPermission('view_products')) {
      return null;
    }
    return _productRepository.getByName(name);
  }

  Future<bool> createProduct(Product product) async {
    if (!_sessionManager.hasPermission('edit_products')) {
      throw AuthorizationException('edit_products');
    }

    if (!_isValidProduct(product)) return false;

    if (product.categoryId != null) {
      final category =
          await _categoryRepository.getById(product.categoryId!);
      if (category == null) {
        // Validation failed: clean up any image that was already stored on
        // disk during the pick step so we don’t leave an orphan file.
        await _imageService.deleteImage(product.imageUrl);
        return false;
      }
    }

    int? productId;
    try {
      productId = await _productRepository.insert(product);
    } catch (e) {
      // Database insert failed: clean up the staged image.
      await _imageService.deleteImage(product.imageUrl);
      rethrow;
    }

    // Record the primary image as an attachment so it follows the unified
    // attachment lifecycle. Failures are logged but do not break the product.
    if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      try {
        await _attachmentService.addAttachment(
          entityType: 'product',
          entityId: productId,
          relativePath: product.imageUrl!,
          attachmentType: 'primary_image',
        );
      } catch (_) {
        // Attachment bookkeeping failed but the product and image are still
        // valid. The legacy image path remains the source of truth.
      }
    }

    await _activityLogService.logActivity(
      action: 'create_product',
      entity: 'product',
      entityId: productId,
      details: 'Created product: ${product.name}',
    );
    return true;
  }

  Future<bool> updateProduct(Product product) async {
    if (!_sessionManager.hasPermission('edit_products')) {
      throw AuthorizationException('edit_products');
    }

    if (!_isValidProduct(product)) return false;

    if (product.categoryId != null) {
      final category =
          await _categoryRepository.getById(product.categoryId!);
      if (category == null) {
        return false;
      }
    }

    // Capture the previous image path BEFORE updating so that, once the
    // database write has succeeded, we can safely delete the old image file
    // only after the new state is durably persisted.
    final existing = product.id != null
        ? await _productRepository.getById(product.id!)
        : null;
    final oldImagePath = existing?.imageUrl;
    final imageChanged =
        oldImagePath != product.imageUrl;

    await _productRepository.update(product);

    if (imageChanged) {
      // Replace the attachment record and delete the old physical file.
      await _attachmentService.replacePrimaryImage(
        'product',
        product.id!,
        product.imageUrl,
        null,
      );

      // Clean up the old image file in case the product predates the
      // attachment table and has no attachment row.
      if (oldImagePath != null && oldImagePath.isNotEmpty) {
        await _imageService.deleteImage(oldImagePath);
      }
    } else if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      // Ensure a primary-image attachment row exists for products created
      // before the attachment system.
      final primary = await _attachmentService.getPrimaryImageAttachment(
        'product',
        product.id!,
      );
      if (primary == null) {
        await _attachmentService.addAttachment(
          entityType: 'product',
          entityId: product.id!,
          relativePath: product.imageUrl!,
          attachmentType: 'primary_image',
        );
      }
    }

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

    final product = await _productRepository.getById(id);
    if (product == null) {
      return false;
    }

    final result = await _trashService.moveToTrash(
      entityType: 'product',
      entityId: id,
      entityName: product.name,
      snapshotJson: TrashService.snapshotForProduct(product),
    );

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'delete_product',
        entity: 'product',
        entityId: id,
        details: 'Soft-deleted product: ${product.name}',
      );
    }

    return result.success;
  }

  Future<bool> restoreProduct(int id) async {
    if (!_sessionManager.hasPermission('restore_trash')) {
      throw AuthorizationException('restore_trash');
    }

    final result = await _trashService.restoreByEntity('product', id);

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'restore_product',
        entity: 'product',
        entityId: id,
        details: 'Restored product from trash',
      );
    }

    return result.success;
  }

  Future<bool> permanentlyDeleteProduct(int id) async {
    if (!_sessionManager.hasPermission('delete_products')) {
      throw AuthorizationException('delete_products');
    }

    final result = await _trashService.permanentDeleteByEntity('product', id);

    if (result.success) {
      await _activityLogService.logActivity(
        action: 'permanently_delete_product',
        entity: 'product',
        entityId: id,
        details: 'Permanently deleted product',
      );
    }

    return result.success;
  }

  bool _isValidProduct(Product product) {
    if (product.name.isEmpty) return false;
    if (product.price <= 0) return false;
    if (product.stock < 0) return false;
    if (product.minStock < 0) return false;
    if (product.categoryId == null) return false;
    return true;
  }
}
