import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/attachment.dart';

/// Data access for the generic `attachments` table.
///
/// Attachments are linked to an entity by `entity_type` + `entity_id`
/// and follow that entity's soft-delete lifecycle.
class AttachmentDao extends BaseDao<Attachment> {
  @override
  String get tableName => 'attachments';

  @override
  Attachment fromMap(Map<String, dynamic> map) => Attachment.fromMap(map);

  Future<List<Attachment>> getByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Attachment>> getActiveByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Attachment>> getDeletedByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NOT NULL',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<int> softDeleteByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    return executor.update(
      tableName,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
      whereArgs: [entityType, entityId],
    );
  }

  Future<int> restoreByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    return executor.update(
      tableName,
      {'deleted_at': null},
      where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NOT NULL',
      whereArgs: [entityType, entityId],
    );
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

  Future<List<Attachment>> getByAttachmentType(
    String entityType,
    int entityId,
    String attachmentType, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where:
          'entity_type = ? AND entity_id = ? AND attachment_type = ? AND deleted_at IS NULL',
      whereArgs: [entityType, entityId, attachmentType],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
