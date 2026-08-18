import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

class TrashService {
  final TrashRepository _trashRepository = TrashRepository();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();

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
      return false;
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
    if (!_sessionManager.hasPermission('view_trash')) {
      return false;
    }

    switch (entityType) {
      case 'product':
        await _productRepository.delete(entityId);
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
    if (!_sessionManager.hasPermission('view_trash')) {
      return false;
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
