import 'package:sqflite/sqflite.dart';
import 'package:pinoy_pos/core/database.dart';

abstract class BaseDao<T> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get db => _dbHelper.database;

  String get tableName;
  T fromMap(Map<String, dynamic> map);

  Future<int> insert(T item) async {
    final database = await db;
    return await database.insert(tableName, (item as dynamic).toMap());
  }

  Future<int> update(T item) async {
    final database = await db;
    final id = (item as dynamic).id;
    return await database.update(
      tableName,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    final database = await db;
    return await database.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> softDelete(int id) async {
    final database = await db;
    return await database.update(
      tableName,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> restore(int id) async {
    final database = await db;
    return await database.update(
      tableName,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<T?> getById(int id) async {
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

  Future<List<T>> getAll({String? where, List<Object?>? whereArgs}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<T>> getAllActive() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'deleted_at IS NULL',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<T>> getDeleted() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'deleted_at IS NOT NULL',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
