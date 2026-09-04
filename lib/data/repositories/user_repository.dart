import 'package:pinoy_pos/data/dao/user_dao.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:sqflite/sqflite.dart';

class UserRepository {
  final UserDao _userDao = UserDao();

  Future<int> insert(User user, {DatabaseExecutor? txn}) =>
      _userDao.insert(user, txn: txn);
  Future<int> update(User user, {DatabaseExecutor? txn}) =>
      _userDao.update(user, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _userDao.delete(id, txn: txn);
  Future<int> softDelete(int id, {DatabaseExecutor? txn}) =>
      _userDao.softDelete(id, txn: txn);
  Future<int> restore(int id, {DatabaseExecutor? txn}) =>
      _userDao.restore(id, txn: txn);
  Future<int> permanentlyDelete(int id, {DatabaseExecutor? txn}) =>
      _userDao.permanentlyDelete(id, txn: txn);
  Future<User?> getById(int id, {DatabaseExecutor? txn}) =>
      _userDao.getById(id, txn: txn);
  Future<User?> getByIdWithDeleted(int id, {DatabaseExecutor? txn}) =>
      _userDao.getByIdWithDeleted(id, txn: txn);
  Future<List<User>> getAll({DatabaseExecutor? txn}) =>
      _userDao.getAll(txn: txn);
  Future<List<User>> getAllActive({DatabaseExecutor? txn}) =>
      _userDao.getAllActive(txn: txn);
  Future<List<User>> getDeleted({DatabaseExecutor? txn}) =>
      _userDao.getDeleted(txn: txn);
  Future<User?> getByUsername(String username, {DatabaseExecutor? txn}) =>
      _userDao.getByUsername(username, txn: txn);
  Future<User?> getByUsernameWithDeleted(String username,
          {DatabaseExecutor? txn}) =>
      _userDao.getByUsernameWithDeleted(username, txn: txn);
  Future<List<User>> getByRole(UserRole role, {DatabaseExecutor? txn}) =>
      _userDao.getByRole(role, txn: txn);
  Future<List<User>> getActiveUsers({DatabaseExecutor? txn}) =>
      _userDao.getActiveUsers(txn: txn);
  Future<void> updateLastLogin(int userId, {DatabaseExecutor? txn}) =>
      _userDao.updateLastLogin(userId, txn: txn);
  Future<void> toggleActive(int userId, bool isActive, {DatabaseExecutor? txn}) =>
      _userDao.toggleActive(userId, isActive, txn: txn);
}
