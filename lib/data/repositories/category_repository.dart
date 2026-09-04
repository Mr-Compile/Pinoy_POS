import 'package:pinoy_pos/data/dao/category_dao.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:sqflite/sqflite.dart';

class CategoryRepository {
  final CategoryDao _categoryDao = CategoryDao();

  Future<int> insert(Category category, {DatabaseExecutor? txn}) =>
      _categoryDao.insert(category, txn: txn);
  Future<int> update(Category category, {DatabaseExecutor? txn}) =>
      _categoryDao.update(category, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _categoryDao.delete(id, txn: txn);
  Future<int> softDelete(int id, {DatabaseExecutor? txn}) =>
      _categoryDao.softDelete(id, txn: txn);
  Future<int> restore(int id, {DatabaseExecutor? txn}) =>
      _categoryDao.restore(id, txn: txn);
  Future<Category?> getById(int id, {DatabaseExecutor? txn}) =>
      _categoryDao.getById(id, txn: txn);
  Future<List<Category>> getAll() => _categoryDao.getAll();
  Future<List<Category>> getAllActive() => _categoryDao.getAllActive();
  Future<List<Category>> getDeleted() => _categoryDao.getDeleted();
  Future<Category?> getByName(String name, {DatabaseExecutor? txn}) =>
      _categoryDao.getByName(name, txn: txn);
  Future<List<Category>> getActiveCategories() =>
      _categoryDao.getActiveCategories();
}
