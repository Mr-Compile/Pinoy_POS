import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/export_history_dao.dart';
import 'package:pinoy_pos/data/models/export_history.dart';

class ExportHistoryRepository {
  final ExportHistoryDao _exportHistoryDao = ExportHistoryDao();

  Future<int> insert(ExportHistory exportHistory, {DatabaseExecutor? txn}) =>
      _exportHistoryDao.insert(exportHistory, txn: txn);

  Future<int> update(ExportHistory exportHistory, {DatabaseExecutor? txn}) =>
      _exportHistoryDao.update(exportHistory, txn: txn);

  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _exportHistoryDao.delete(id, txn: txn);

  Future<int> softDelete(int id, {DatabaseExecutor? txn}) =>
      _exportHistoryDao.softDelete(id, txn: txn);

  Future<ExportHistory?> getById(int id, {DatabaseExecutor? txn}) =>
      _exportHistoryDao.getById(id, txn: txn);

  Future<List<ExportHistory>> getAll({DatabaseExecutor? txn}) =>
      _exportHistoryDao.getAll(txn: txn);

  Future<List<ExportHistory>> getAllActive({DatabaseExecutor? txn, int? limit}) =>
      _exportHistoryDao.getAllActive(txn: txn, limit: limit);

  Future<List<ExportHistory>> getByStatus(
    String status, {
    int? limit,
    DatabaseExecutor? txn,
  }) =>
      _exportHistoryDao.getByStatus(status, limit: limit, txn: txn);

  Future<List<ExportHistory>> getByCreatedBy(
    int createdBy, {
    int? limit,
    DatabaseExecutor? txn,
  }) =>
      _exportHistoryDao.getByCreatedBy(createdBy, limit: limit, txn: txn);

  Future<List<ExportHistory>> getByCreatedByAndStatus(
    int createdBy,
    String status, {
    int? limit,
    DatabaseExecutor? txn,
  }) =>
      _exportHistoryDao.getByCreatedByAndStatus(
        createdBy,
        status,
        limit: limit,
        txn: txn,
      );

  Future<List<ExportHistory>> getSubmittedToOwner({
    int? limit,
    DatabaseExecutor? txn,
  }) =>
      _exportHistoryDao.getSubmittedToOwner(limit: limit, txn: txn);

  Future<List<ExportHistory>> getRecent({
    int? createdBy,
    int? limit,
    DatabaseExecutor? txn,
  }) =>
      _exportHistoryDao.getRecent(
        createdBy: createdBy,
        limit: limit,
        txn: txn,
      );
}
