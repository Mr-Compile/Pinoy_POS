import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/image_service.dart';

class TrashService {
  final TrashRepository _trashRepository = TrashRepository();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();
  final ImageService _imageService = ImageService();

  Future<List<TrashItem>> getAllTrash() async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    return _trashRepository.getAll();
  }

  Future<List<TrashItem>> getByEntityType(String entityType) async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    return _trashRepository.getByEntityType(entityType);
  }

  Future<bool> moveToTrash({
    required String entityType,
    required int entityId,
    String? entityName,
  }) async {
    final trashItem = TrashItem(
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      deletedBy: _sessionManager.currentUser?.id,
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await _trashRepository.insert(trashItem);
    return true;
  }

  Future<bool> restoreFromTrash(int trashId, String entityType, int entityId) async {
    if (!_sessionManager.hasPermission('restore_trash')) {
      throw AuthorizationException('restore_trash');
    }

    switch (entityType) {
      case 'product':
        await _productRepository.restore(entityId);
        break;
      case 'category':
        await _categoryRepository.restore(entityId);
        break;
      case 'user':
        await _userRepository.restore(entityId);
        break;
    }

    await _trashRepository.delete(trashId);
    return true;
  }

  Future<bool> permanentDelete(int trashId, String entityType, int entityId) async {
    final requiredPermission = switch (entityType) {
      'product' => 'delete_products',
      'category' => 'delete_categories',
      'user' => 'delete_users',
      _ => 'restore_trash',
    };
    if (!_sessionManager.hasPermission(requiredPermission)) {
      throw AuthorizationException(requiredPermission);
    }

    switch (entityType) {
      case 'product':
        // Capture the image path before destroying the row so the file can
        // be cleaned up afterwards, leaving no orphan image behind.
        final product = await _productRepository.getById(entityId);
        final imagePath = product?.imageUrl;
        await _productRepository.delete(entityId);
        await _imageService.deleteImage(imagePath);
        break;
      case 'category':
        await _categoryRepository.delete(entityId);
        break;
      case 'user':
        await _userRepository.permanentlyDelete(entityId);
        break;
    }

    await _trashRepository.delete(trashId);
    return true;
  }

  Future<bool> emptyTrash() async {
    final required = ['delete_products', 'delete_categories', 'delete_users'];
    final missing = required
        .where((p) => !_sessionManager.hasPermission(p))
        .toList();
    if (missing.isNotEmpty) {
      throw AuthorizationException(missing.first);
    }

    final items = await _trashRepository.getAll();
    for (var item in items) {
      if (item.id != null) {
        await _trashRepository.delete(item.id!);
      }
    }
    return true;
  }
}
