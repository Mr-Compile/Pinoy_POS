import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';

class CategoryService {
  final CategoryRepository _categoryRepository = CategoryRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();

  Future<List<Category>> getActiveCategories() async {
    if (!_sessionManager.hasPermission('view_categories')) {
      return [];
    }
    return _categoryRepository.getActiveCategories();
  }

  Future<List<Category>> getAllCategories() async {
    if (!_sessionManager.hasPermission('view_categories')) {
      return [];
    }
    return _categoryRepository.getAll();
  }

  Future<bool> changeCategoryStatus(int id, bool isActive) async {
    if (!_sessionManager.hasPermission('edit_categories')) {
      throw AuthorizationException('edit_categories');
    }

    await _categoryRepository.update(
      (await _categoryRepository.getById(id))!.copyWith(isActive: isActive),
    );
    await _activityLogService.logActivity(
      action: 'change_category_status',
      entity: 'category',
      entityId: id,
      details: isActive ? 'Activated category' : 'Deactivated category',
    );
    return true;
  }

  Future<Category?> getCategoryById(int id) async {
    if (!_sessionManager.hasPermission('view_categories')) {
      return null;
    }
    return _categoryRepository.getById(id);
  }

  Future<bool> createCategory(Category category) async {
    if (!_sessionManager.hasPermission('edit_categories')) {
      throw AuthorizationException('edit_categories');
    }

    if (category.name.isEmpty) {
      return false;
    }

    final existing = await _categoryRepository.getByName(category.name);
    if (existing != null) {
      return false;
    }

    await _categoryRepository.insert(category);
    await _activityLogService.logActivity(
      action: 'create_category',
      entity: 'category',
      details: 'Created category: ${category.name}',
    );
    return true;
  }

  Future<bool> updateCategory(Category category) async {
    if (!_sessionManager.hasPermission('edit_categories')) {
      throw AuthorizationException('edit_categories');
    }

    if (category.name.isEmpty) {
      return false;
    }

    final existing = await _categoryRepository.getByName(category.name);
    if (existing != null && existing.id != category.id) {
      return false;
    }

    await _categoryRepository.update(category);
    await _activityLogService.logActivity(
      action: 'update_category',
      entity: 'category',
      entityId: category.id,
      details: 'Updated category: ${category.name}',
    );
    return true;
  }

  Future<bool> deleteCategory(int id) async {
    if (!_sessionManager.hasPermission('delete_categories')) {
      throw AuthorizationException('delete_categories');
    }

    await _categoryRepository.softDelete(id);
    await _activityLogService.logActivity(
      action: 'delete_category',
      entity: 'category',
      entityId: id,
      details: 'Soft-deleted category',
    );
    return true;
  }

  Future<bool> restoreCategory(int id) async {
    if (!_sessionManager.hasPermission('delete_categories')) {
      throw AuthorizationException('delete_categories');
    }

    await _categoryRepository.restore(id);
    await _activityLogService.logActivity(
      action: 'restore_category',
      entity: 'category',
      entityId: id,
      details: 'Restored category from trash',
    );
    return true;
  }
}
