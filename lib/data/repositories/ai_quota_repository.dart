import 'package:pinoy_pos/data/dao/ai_quota_dao.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:sqflite/sqflite.dart';

class AIQuotaRepository {
  final AIQuotaDao _aiQuotaDao = AIQuotaDao();

  Future<int> insert(AIQuota aiQuota, {DatabaseExecutor? txn}) =>
      _aiQuotaDao.insert(aiQuota, txn: txn);

  Future<int> update(AIQuota aiQuota, {DatabaseExecutor? txn}) =>
      _aiQuotaDao.update(aiQuota, txn: txn);

  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _aiQuotaDao.delete(id, txn: txn);

  Future<AIQuota?> getById(int id, {DatabaseExecutor? txn}) =>
      _aiQuotaDao.getById(id, txn: txn);

  Future<AIQuota?> getByUserId(int userId) => _aiQuotaDao.getByUserId(userId);

  Future<List<AIQuota>> getAll({DatabaseExecutor? txn}) =>
      _aiQuotaDao.getAll(txn: txn);

  Future<List<AIQuota>> getForActiveUsers({DatabaseExecutor? txn}) =>
      _aiQuotaDao.getForActiveUsers(txn: txn);

  Future<void> updateByUserId(
    int userId, {
    required Map<String, dynamic> values,
    DatabaseExecutor? txn,
  }) =>
      _aiQuotaDao.updateByUserId(userId, values: values, txn: txn);

  Future<void> resetDailyUsage(
    int userId, {
    required DateTime quotaDate,
    required DateTime lastResetAt,
    DatabaseExecutor? txn,
  }) =>
      _aiQuotaDao.resetDailyUsage(
        userId,
        quotaDate: quotaDate,
        lastResetAt: lastResetAt,
        txn: txn,
      );

  Future<void> resetAllDailyUsage({
    required DateTime quotaDate,
    required DateTime lastResetAt,
    DatabaseExecutor? txn,
  }) =>
      _aiQuotaDao.resetAllDailyUsage(
        quotaDate: quotaDate,
        lastResetAt: lastResetAt,
        txn: txn,
      );

  Future<void> updateDailyUsage(
    int userId,
    int dailyUsage, {
    DatabaseExecutor? txn,
  }) =>
      _aiQuotaDao.updateDailyUsage(userId, dailyUsage, txn: txn);

  Future<void> updateDailyQuota(
    int userId,
    int dailyQuota, {
    DatabaseExecutor? txn,
  }) =>
      _aiQuotaDao.updateDailyQuota(userId, dailyQuota, txn: txn);
}
