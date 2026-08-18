import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/user.dart';

class UserDao extends BaseDao<User> {
  @override
  String get tableName => 'users';

  @override
  User fromMap(Map<String, dynamic> map) => User.fromMap(map);

  /// Returns a non-deleted user matching [username], or null.
  Future<User?> getByUsername(String username) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'username = ? AND deleted_at IS NULL',
      whereArgs: [username],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Returns any user matching [username] including soft-deleted ones.
  Future<User?> getByUsernameWithDeleted(String username) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Returns a user by [id] including soft-deleted ones.
  Future<User?> getByIdWithDeleted(int id) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<User>> getByRole(UserRole role) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'role = ? AND deleted_at IS NULL',
      whereArgs: [role.name],
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<User>> getActiveUsers() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'is_active = 1 AND deleted_at IS NULL',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<void> updateLastLogin(int userId) async {
    final database = await db;
    await database.update(
      tableName,
      {'last_login': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> toggleActive(int userId, bool isActive) async {
    final database = await db;
    await database.update(
      tableName,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updateColorPreference(int userId, String colorPreference) async {
    final database = await db;
    await database.update(
      tableName,
      {
        'color_preference': colorPreference,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Permanently deletes a user row from the database.
  /// This is irreversible and should only be called from the Trash system.
  Future<int> permanentlyDelete(int id) async {
    final database = await db;
    return await database.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
