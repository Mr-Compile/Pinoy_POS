import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';

class TrashDao {
  Future<int> insert(TrashItem trashItem) async {
    final database = await DatabaseHelper().database;
    return database.insert('trash', trashItem.toMap());
  }

  Future<int> delete(int id) async {
    final database = await DatabaseHelper().database;
    return database.delete('trash', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteByEntity(String entityType, int entityId) async {
    final database = await DatabaseHelper().database;
    return database.delete(
      'trash',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  Future<List<TrashItem>> getAll() async {
    final database = await DatabaseHelper().database;
    final maps = await database.query('trash', orderBy: 'deleted_at DESC');
    return maps.map((map) => TrashItem.fromMap(map)).toList();
  }

  Future<List<TrashItem>> getByEntityType(String entityType) async {
    final database = await DatabaseHelper().database;
    final maps = await database.query(
      'trash',
      where: 'entity_type = ?',
      whereArgs: [entityType],
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => TrashItem.fromMap(map)).toList();
  }

  Future<TrashItem?> getByEntity(String entityType, int entityId) async {
    final database = await DatabaseHelper().database;
    final maps = await database.query(
      'trash',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TrashItem.fromMap(maps.first);
  }
}
