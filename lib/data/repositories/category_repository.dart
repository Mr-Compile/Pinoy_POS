import 'package:pinoy_pos/data/dao/category_dao.dart';
import 'package:pinoy_pos/data/models/category.dart';

class CategoryRepository {
  final CategoryDao _categoryDao = CategoryDao();

  Future<int> insert(Category category) => _categoryDao.insert(category);
  Future<int> update(Category category) => _categoryDao.update(category);
  Future<int> delete(int id) => _categoryDao.delete(id);
  Future<int> softDelete(int id) => _categoryDao.softDelete(id);
  Future<int> restore(int id) => _categoryDao.restore(id);
  Future<Category?> getById(int id) => _categoryDao.getById(id);
  Future<List<Category>> getAll() => _categoryDao.getAll();
  Future<List<Category>> getAllActive() => _categoryDao.getAllActive();
  Future<List<Category>> getDeleted() => _categoryDao.getDeleted();
  Future<Category?> getByName(String name) => _categoryDao.getByName(name);
  Future<List<Category>> getActiveCategories() => _categoryDao.getActiveCategories();
}
