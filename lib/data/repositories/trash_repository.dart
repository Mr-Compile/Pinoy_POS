import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/trash_dao.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';

class TrashRepository {
  final TrashDao _trashDao = TrashDao();

  Future<int> insert(TrashItem trashItem, {DatabaseExecutor? txn}) =>
      _trashDao.insert(trashItem, txn: txn);

  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _trashDao.delete(id, txn: txn);

  Future<int> deleteByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _trashDao.deleteByEntity(entityType, entityId, txn: txn);

  Future<List<TrashItem>> getAll({
    String? where,
    List<Object?>? whereArgs,
    DatabaseExecutor? txn,
  }) =>
      _trashDao.getAll(
        where: where,
        whereArgs: whereArgs,
        txn: txn,
      );

  Future<List<TrashItem>> getByEntityType(
    String entityType, {
    DatabaseExecutor? txn,
  }) =>
      _trashDao.getByEntityType(entityType, txn: txn);

  Future<TrashItem?> getByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _trashDao.getByEntity(entityType, entityId, txn: txn);

  Future<TrashItem?> getById(int id, {DatabaseExecutor? txn}) =>
      _trashDao.getById(id, txn: txn);

  Future<List<TrashItem>> getExpired({DatabaseExecutor? txn}) =>
      _trashDao.getExpired(txn: txn);
}
