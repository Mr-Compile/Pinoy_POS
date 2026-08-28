import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_usage.dart';
import 'package:pinoy_pos/data/repositories/ai_usage_repository.dart';
import 'package:pinoy_pos/services/ai_quota_service.dart';

/// Service for recording and enforcing AI usage limits.
///
/// Quota enforcement has moved to [AIQuotaService]. This service keeps
/// recording individual AI queries in the historical [ai_usage] table and
/// delegates all quota questions to [AIQuotaService].
class AIUsageService {
  final AIUsageRepository _aiUsageRepository = AIUsageRepository();
  final AIQuotaService _aiQuotaService = AIQuotaService();
  final SessionManager _sessionManager = SessionManager();

  /// Returns how many AI queries the current user has consumed today.
  Future<int> getTodayUsageCount() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return 0;
    }
    if (_sessionManager.currentUser == null) {
      return 0;
    }
    return _aiQuotaService.getTodayUsageCount();
  }

  /// Returns true when the current user is still under their daily AI quota.
  Future<bool> canUseAI() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return false;
    }
    return _aiQuotaService.canUseAI();
  }

  /// Records a successful AI query.
  ///
  /// Returns true if the query was recorded. Returns false if the current
  /// user has exhausted their daily quota. The historical [ai_usage] row is
  /// persisted on success.
  Future<bool> recordQuery(String query, String? response) async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      throw AuthorizationException('use_ai_advisor');
    }
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
    await _aiQuotaService.recordQuery(query);

    return true;
  }

  /// Returns the recent AI query history for the current user.
  Future<List<AIUsage>> getQueryHistory() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return [];
    }
    if (_sessionManager.currentUser == null) {
      return [];
    }
    return _aiUsageRepository.getByUserId(_sessionManager.currentUser!.id!);
  }

  /// Returns the number of remaining AI queries for the current user.
  Future<int> getRemainingQueries() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return 0;
    }
    return _aiQuotaService.getRemainingQueries();
  }

  /// Returns the daily AI quota for the current user.
  Future<int> getDailyQuota() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return 0;
    }
    if (_sessionManager.currentUser == null) {
      return 0;
    }
    final quota = await _aiQuotaService.getQuotaForUser(_sessionManager.currentUser!.id!);
    return quota.dailyQuota;
  }
}

