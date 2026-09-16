import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:pinoy_pos/data/repositories/ai_quota_repository.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

class AIQuotaOperationResult {
  final bool success;
  final String message;
  final AIQuota? quota;

  AIQuotaOperationResult({
    required this.success,
    this.message = '',
    this.quota,
  });
}

/// Manages the global daily AI quota, per-user usage tracking, daily reset,
/// and SuperAdmin-guarded administrative actions.
///
/// The quota limit is global: `settings.ai_daily_quota` applies to every
/// user. There is no per-user quota override — `ai_quota` rows only track
/// each user's daily usage counter.
///
/// This service is the single source of truth for quota enforcement. The
/// historical [ai_usage] table is kept for query history/auditing but is no
/// longer used to enforce the daily limit.
class AIQuotaService {
  final AIQuotaRepository _aiQuotaRepository = AIQuotaRepository();
  final SettingsRepository _settingsRepository = SettingsRepository();
  final SettingsService _settingsService = SettingsService();
  final ActivityLogService _activityLogService = ActivityLogService();
  final SessionManager _sessionManager = SessionManager();

  /// Returns today's start-of-day date.
  DateTime _today() {
    return startOfDay(DateTime.now());
  }

  /// Returns the current user id, or throws if not authenticated.
  int _currentUserId() {
    final user = _sessionManager.currentUser;
    if (user == null || user.id == null) {
      throw AuthorizationException('use_ai_advisor');
    }
    return user.id!;
  }

  /// Ensures the user has a usage row, creating an empty counter if it is
  /// missing.
  Future<AIQuota> ensureQuotaForUser(int userId) async {
    final existing = await _aiQuotaRepository.getByUserId(userId);
    if (existing != null) return existing;

    final now = DateTime.now();

    final quota = AIQuota(
      userId: userId,
      dailyUsage: 0,
      quotaDate: now,
      lastResetAt: now,
    );

    final id = await _aiQuotaRepository.insert(quota);
    return quota.copyWith(id: id);
  }

  /// Returns the usage row for [userId], automatically creating it and/or
  /// resetting the daily counter when the date has changed.
  Future<AIQuota> getQuotaForUser(int userId) async {
    final quota = await ensureQuotaForUser(userId);
    final today = _today();
    final quotaDate = DateTime(
      quota.quotaDate.year,
      quota.quotaDate.month,
      quota.quotaDate.day,
    );

    if (quotaDate != today) {
      final now = DateTime.now();
      await _aiQuotaRepository.resetDailyUsage(
        userId,
        quotaDate: now,
        lastResetAt: now,
      );
      return quota.copyWith(
        dailyUsage: 0,
        quotaDate: now,
        lastResetAt: now,
      );
    }

    return quota;
  }

  /// Returns the usage row for the current user, or an empty counter if no
  /// user is signed in.
  Future<AIQuota> _currentUserQuota() async {
    final user = _sessionManager.currentUser;
    if (user == null || user.id == null) {
      return AIQuota(
        userId: 0,
        dailyUsage: 0,
        quotaDate: DateTime.now(),
      );
    }
    return getQuotaForUser(user.id!);
  }

  /// Returns true when the current user is under the global daily AI quota.
  Future<bool> canUseAI() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return false;
    }

    final quota = await _currentUserQuota();
    return quota.dailyUsage < await getDefaultQuota();
  }

  /// Records a successful AI query against the current user's daily quota.
  ///
  /// This should only be called after [canUseAI] returns true. It increments
  /// [dailyUsage] and does not touch the historical [ai_usage] table.
  Future<void> recordQuery(String query) async {
    final userId = _currentUserId();
    final quota = await getQuotaForUser(userId);

    if (quota.dailyUsage >= await getDefaultQuota()) {
      return;
    }

    await _aiQuotaRepository.updateDailyUsage(userId, quota.dailyUsage + 1);
  }

  /// Returns the number of AI queries used today by the current user.
  Future<int> getTodayUsageCount() async {
    final quota = await _currentUserQuota();
    return quota.dailyUsage;
  }

  /// Returns the number of remaining AI queries for the current user.
  Future<int> getRemainingQueries() async {
    final quota = await _currentUserQuota();
    final limit = await getDefaultQuota();
    return (limit - quota.dailyUsage).clamp(0, limit);
  }

  /// Returns the current default daily AI quota.
  Future<int> getDefaultQuota() async {
    final settings = await _settingsRepository.getSettings();
    return settings?.aiDailyQuota ?? AppConstants.defaultDailyAIQuota;
  }

  /// Validates that [value] is a positive integer within the allowed max.
  AIQuotaOperationResult? _validateQuotaValue(int value) {
    if (value <= 0) {
      return AIQuotaOperationResult(
        success: false,
        message: 'Quota must be a positive integer',
      );
    }
    if (value > AppConstants.maxDailyAIQuota) {
      return AIQuotaOperationResult(
        success: false,
        message: 'Quota cannot exceed ${AppConstants.maxDailyAIQuota}',
      );
    }
    return null;
  }

  /// Verifies [verified] by checking the SuperAdmin password. [verified] is
  /// a flag, but real callers must supply the correct password. This method
  /// centralises the check and never logs the password.
  AIQuotaOperationResult? _requireVerification(bool verified) {
    if (!verified) {
      return AIQuotaOperationResult(
        success: false,
        message: 'SuperAdmin verification is required',
      );
    }
    return null;
  }

  /// Updates the global daily quota for the application.
  ///
  /// [verified] must be the result of a successful SuperAdmin password check.
  /// The new value applies to every user immediately — the limit is global.
  Future<AIQuotaOperationResult> setDefaultQuota({
    required int value,
    required bool verified,
  }) async {
    final verificationError = _requireVerification(verified);
    if (verificationError != null) return verificationError;

    final valueError = _validateQuotaValue(value);
    if (valueError != null) return valueError;

    final currentUser = _sessionManager.currentUser;
    if (currentUser == null || currentUser.id == null) {
      return AIQuotaOperationResult(
        success: false,
        message: 'You must be logged in to perform this action',
      );
    }

    if (!_sessionManager.hasPermission('manage_ai_quota')) {
      throw AuthorizationException('manage_ai_quota');
    }

    final oldDefault = await getDefaultQuota();

    final settings = await _settingsService.getSettings();

    final updated = await _settingsService.updateSettings(
      settings.copyWith(aiDailyQuota: value, updatedAt: DateTime.now()),
    );
    if (!updated) {
      return AIQuotaOperationResult(
        success: false,
        message: 'Failed to update settings',
      );
    }

    await _logActivity(
      'AI_QUOTA_DEFAULT_CHANGED',
      details: 'Default daily quota changed from $oldDefault to $value',
    );

    return AIQuotaOperationResult(
      success: true,
      message: 'Default quota updated to $value',
    );
  }

  /// Resets today's usage for a single user.
  Future<AIQuotaOperationResult> resetUserUsage(
    int userId, {
    required bool verified,
  }) async {
    final verificationError = _requireVerification(verified);
    if (verificationError != null) return verificationError;

    if (!_sessionManager.hasPermission('manage_ai_quota')) {
      throw AuthorizationException('manage_ai_quota');
    }

    final quota = await ensureQuotaForUser(userId);
    final oldUsage = quota.dailyUsage;
    final now = DateTime.now();

    await _aiQuotaRepository.resetDailyUsage(
      userId,
      quotaDate: now,
      lastResetAt: now,
    );

    await _logActivity(
      'AI_QUOTA_USER_RESET',
      entityId: userId,
      details: 'Reset daily usage from $oldUsage to 0',
    );

    return AIQuotaOperationResult(
      success: true,
      message: 'User daily usage reset',
    );
  }

  /// Resets today's usage for all active users.
  Future<AIQuotaOperationResult> resetAllUserUsage({
    required bool verified,
  }) async {
    final verificationError = _requireVerification(verified);
    if (verificationError != null) return verificationError;

    if (!_sessionManager.hasPermission('manage_ai_quota')) {
      throw AuthorizationException('manage_ai_quota');
    }

    final now = DateTime.now();
    final activeQuotas = await _aiQuotaRepository.getForActiveUsers();

    await _aiQuotaRepository.resetAllDailyUsage(
      quotaDate: now,
      lastResetAt: now,
    );

    await _logActivity(
      'AI_QUOTA_ALL_RESET',
      details: 'Reset daily usage for ${activeQuotas.length} active users',
    );

    return AIQuotaOperationResult(
      success: true,
      message: 'Daily usage reset for all active users',
    );
  }

  Future<void> _logActivity(
    String action, {
    String? details,
    int? entityId,
  }) async {
    final user = _sessionManager.currentUser;
    if (user == null || user.id == null) return;

    await _activityLogService.logActivity(
      action: action,
      entity: 'ai_quota',
      entityId: entityId,
      details: details,
    );
  }
}




