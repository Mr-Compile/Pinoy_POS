import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/data/models/ai_usage.dart';
import 'package:pinoy_pos/data/repositories/ai_usage_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class AIUsageService {
  final AIUsageRepository _aiUsageRepository = AIUsageRepository();
  final AuthService _authService = AuthService();

  Future<int> getTodayUsageCount() async {
    if (_authService.currentUser == null) {
      return 0;
    }
    return _aiUsageRepository.getTodayCount(_authService.currentUser!.id!);
  }

  Future<bool> canUseAI() async {
    final todayCount = await getTodayUsageCount();
    return todayCount < AppConstants.maxDailyAIQueries;
  }

  Future<bool> recordQuery(String query, String? response) async {
    if (_authService.currentUser == null) {
      return false;
    }

    if (!await canUseAI()) {
      return false;
    }

    final aiUsage = AIUsage(
      userId: _authService.currentUser!.id!,
      query: query,
      response: response,
      createdAt: DateTime.now(),
    );

    await _aiUsageRepository.insert(aiUsage);
    return true;
  }

  Future<List<AIUsage>> getQueryHistory() async {
    if (_authService.currentUser == null) {
      return [];
    }
    return _aiUsageRepository.getByUserId(_authService.currentUser!.id!);
  }
}
