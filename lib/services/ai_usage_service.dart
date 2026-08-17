import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_usage.dart';
import 'package:pinoy_pos/data/repositories/ai_usage_repository.dart';

class AIUsageService {
  final AIUsageRepository _aiUsageRepository = AIUsageRepository();
  final SessionManager _sessionManager = SessionManager();

  Future<int> getTodayUsageCount() async {
    if (_sessionManager.currentUser == null) {
      return 0;
    }
    return _aiUsageRepository.getTodayCount(_sessionManager.currentUser!.id!);
  }

  Future<bool> canUseAI() async {
    final todayCount = await getTodayUsageCount();
    return todayCount < AppConstants.maxDailyAIQueries;
  }

  Future<bool> recordQuery(String query, String? response) async {
    if (_sessionManager.currentUser == null) {
      return false;
    }

    if (!await canUseAI()) {
      return false;
    }

    final aiUsage = AIUsage(
      userId: _sessionManager.currentUser!.id!,
      query: query,
      response: response,
      createdAt: DateTime.now(),
    );

    await _aiUsageRepository.insert(aiUsage);
    return true;
  }

  Future<List<AIUsage>> getQueryHistory() async {
    if (_sessionManager.currentUser == null) {
      return [];
    }
    return _aiUsageRepository.getByUserId(_sessionManager.currentUser!.id!);
  }
}
