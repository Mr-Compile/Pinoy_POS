import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';

/// Data access for the `trash` table.
///
/// Extends [BaseDao] for standard CRUD and adds trash-specific lookups
/// by entity type/entity id. Trash rows are ordered by deletion time.
class TrashDao extends BaseDao<TrashItem> {
  @override
  String get tableName => 'trash';

  @override
  TrashItem fromMap(Map<String, dynamic> map) => TrashItem.fromMap(map);

  @override
  Future<List<TrashItem>> getAll({
    String? where,
    List<Object?>? whereArgs,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<int> deleteByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    return executor.delete(
      tableName,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  Future<List<TrashItem>> getByEntityType(
    String entityType, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'entity_type = ?',
      whereArgs: [entityType],
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<TrashItem?> getByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Returns trash rows whose [expires_at] is in the past.
  Future<List<TrashItem>> getExpired({DatabaseExecutor? txn}) async {
    final executor = txn ?? await db;
    final now = DateTime.now().toIso8601String();
    final maps = await executor.query(
      tableName,
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [now],
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
