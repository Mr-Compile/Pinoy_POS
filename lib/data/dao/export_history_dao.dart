import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/export_history.dart';

class ExportHistoryDao extends BaseDao<ExportHistory> {
  @override
  String get tableName => 'export_history';

  @override
  ExportHistory fromMap(Map<String, dynamic> map) => ExportHistory.fromMap(map);

  @override
  Future<List<ExportHistory>> getAllActive({
    DatabaseExecutor? txn,
    int? limit,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }

  Future<List<ExportHistory>> getByStatus(
    String status, {
    int? limit,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'status = ? AND deleted_at IS NULL',
      whereArgs: [status],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }

  Future<List<ExportHistory>> getByCreatedBy(
    int createdBy, {
    int? limit,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'created_by = ? AND deleted_at IS NULL',
      whereArgs: [createdBy],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }

  Future<List<ExportHistory>> getByCreatedByAndStatus(
    int createdBy,
    String status, {
    int? limit,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: 'created_by = ? AND status = ? AND deleted_at IS NULL',
      whereArgs: [createdBy, status],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }

  Future<List<ExportHistory>> getSubmittedToOwner({
    int? limit,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where: "status IN ('submitted', 'viewed', 'imported') AND deleted_at IS NULL",
      orderBy: 'submitted_at DESC, created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }

  Future<List<ExportHistory>> getRecent({
    int? createdBy,
    int? limit,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];

    if (createdBy != null) {
      conditions.add('created_by = ?');
      args.add(createdBy);
    }

    final maps = await executor.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(fromMap).toList();
  }
}
