import 'package:sqflite/sqflite.dart';
import 'package:pinoy_pos/core/database.dart';

abstract class BaseDao<T> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get db => _dbHelper.database;

  String get tableName;
  T fromMap(Map<String, dynamic> map);

  Future<DatabaseExecutor> _executor([DatabaseExecutor? txn]) async {
    if (txn != null) return txn;
    return await db;
  }

  Future<int> insert(T item, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    return await executor.insert(tableName, (item as dynamic).toMap() as Map<String, dynamic>);
  }

  Future<int> update(T item, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    final id = (item as dynamic).id;
    return await executor.update(
      tableName,
      (item as dynamic).toMap() as Map<String, dynamic>,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    return await executor.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> softDelete(int id, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    return await executor.update(
      tableName,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> restore(int id, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    return await executor.update(
      tableName,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<T?> getById(int id, {DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    final maps = await executor.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<T>> getAll({String? where, List<Object?>? whereArgs, DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    final maps = await executor.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<T>> getAllActive({DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    final maps = await executor.query(
      tableName,
      where: 'deleted_at IS NULL',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<T>> getDeleted({DatabaseExecutor? txn}) async {
    final executor = await _executor(txn);
    final maps = await executor.query(
      tableName,
      where: 'deleted_at IS NOT NULL',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
