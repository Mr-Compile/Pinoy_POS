import 'package:pinoy_pos/data/dao/ai_usage_dao.dart';
import 'package:pinoy_pos/data/models/ai_usage.dart';

class AIUsageRepository {
  final AIUsageDao _aiUsageDao = AIUsageDao();

  Future<int> insert(AIUsage aiUsage) => _aiUsageDao.insert(aiUsage);
  Future<int> update(AIUsage aiUsage) => _aiUsageDao.update(aiUsage);
  Future<int> delete(int id) => _aiUsageDao.delete(id);
  Future<AIUsage?> getById(int id) => _aiUsageDao.getById(id);
  Future<List<AIUsage>> getAll() => _aiUsageDao.getAll();
  Future<List<AIUsage>> getByUserId(int userId) => _aiUsageDao.getByUserId(userId);
  Future<int> getTodayCount(int userId) => _aiUsageDao.getTodayCount(userId);
}
