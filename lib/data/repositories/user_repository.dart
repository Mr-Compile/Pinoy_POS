import 'package:pinoy_pos/data/dao/user_dao.dart';
import 'package:pinoy_pos/data/models/user.dart';

class UserRepository {
  final UserDao _userDao = UserDao();

  Future<int> insert(User user) => _userDao.insert(user);
  Future<int> update(User user) => _userDao.update(user);
  Future<int> delete(int id) => _userDao.delete(id);
  Future<int> softDelete(int id) => _userDao.softDelete(id);
  Future<int> restore(int id) => _userDao.restore(id);
  Future<User?> getById(int id) => _userDao.getById(id);
  Future<List<User>> getAll() => _userDao.getAll();
  Future<List<User>> getAllActive() => _userDao.getAllActive();
  Future<List<User>> getDeleted() => _userDao.getDeleted();
  Future<User?> getByUsername(String username) => _userDao.getByUsername(username);
  Future<User?> getByUsernameWithDeleted(String username) => _userDao.getByUsernameWithDeleted(username);
  Future<List<User>> getByRole(UserRole role) => _userDao.getByRole(role);
  Future<List<User>> getActiveUsers() => _userDao.getActiveUsers();
  Future<void> updateLastLogin(int userId) => _userDao.updateLastLogin(userId);
  Future<void> toggleActive(int userId, bool isActive) => _userDao.toggleActive(userId, isActive);
}
