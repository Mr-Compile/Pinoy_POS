import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class CategoryService {
  final CategoryRepository _categoryRepository = CategoryRepository();
  final AuthService _authService = AuthService();

  Future<List<Category>> getActiveCategories() async {
    if (!_authService.hasPermission('view_categories')) {
      return [];
    }
    return _categoryRepository.getActiveCategories();
  }

  Future<Category?> getCategoryById(int id) async {
    if (!_authService.hasPermission('view_categories')) {
      return null;
    }
    return _categoryRepository.getById(id);
  }

  Future<bool> createCategory(Category category) async {
    if (!_authService.hasPermission('manage_categories')) {
      return false;
    }

    if (category.name.isEmpty) {
      return false;
    }

    final existing = await _categoryRepository.getByName(category.name);
    if (existing != null) {
      return false;
    }

    await _categoryRepository.insert(category);
    return true;
  }

  Future<bool> updateCategory(Category category) async {
    if (!_authService.hasPermission('manage_categories')) {
      return false;
    }

    if (category.name.isEmpty) {
      return false;
    }

    final existing = await _categoryRepository.getByName(category.name);
    if (existing != null && existing.id != category.id) {
      return false;
    }

    await _categoryRepository.update(category);
    return true;
  }

  Future<bool> deleteCategory(int id) async {
    if (!_authService.hasPermission('manage_categories')) {
      return false;
    }

    await _categoryRepository.softDelete(id);
    return true;
  }

  Future<bool> restoreCategory(int id) async {
    if (!_authService.hasPermission('manage_categories')) {
      return false;
    }

    await _categoryRepository.restore(id);
    return true;
  }
}
