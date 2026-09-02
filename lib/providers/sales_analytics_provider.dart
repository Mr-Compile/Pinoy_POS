import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// UI state for the Sales Analytics / Reports screen.
class SalesAnalyticsState {
  final ReportingPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final SalesAnalytics? analytics;
  final bool isLoading;
  final String? error;
  final Settings? storeInfo;

  const SalesAnalyticsState({
    this.period = ReportingPeriod.thisMonth,
    this.customStart,
    this.customEnd,
    this.analytics,
    this.isLoading = true,
    this.error,
    this.storeInfo,
  });

  SalesAnalyticsState copyWith({
    ReportingPeriod? period,
    DateTime? customStart,
    DateTime? customEnd,
    SalesAnalytics? analytics,
    bool? isLoading,
    String? error,
    Settings? storeInfo,
    bool clearCustomRange = false,
    bool clearError = false,
    bool clearAnalytics = false,
  }) {
    return SalesAnalyticsState(
      period: period ?? this.period,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      analytics: clearAnalytics ? null : (analytics ?? this.analytics),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      storeInfo: storeInfo ?? this.storeInfo,
    );
  }

  bool get hasCustomRange =>
      customStart != null &&
      customEnd != null &&
      period == ReportingPeriod.custom;

  String get periodLabel {
    final analytics = this.analytics;
    if (analytics != null) return formatPeriodLabel(analytics.bounds);
    final bounds = periodBoundsFor(
      period,
      customStart: customStart,
      customEnd: customEnd,
    );
    return formatPeriodLabel(bounds);
  }
}

/// Notifier that loads role-scoped sales analytics for the selected period.
class SalesAnalyticsNotifier extends StateNotifier<SalesAnalyticsState> {
  final SalesAnalyticsService _service;
  final SettingsService _settingsService;

  SalesAnalyticsNotifier()
      : _service = SalesAnalyticsService(),
        _settingsService = SettingsService(),
        super(const SalesAnalyticsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearAnalytics: true,
    );
    try {
      final storeInfo = await _settingsService.getStoreInfo();
      final analytics = await _service.getAnalytics(
        state.period,
        customStart: state.customStart,
        customEnd: state.customEnd,
      );
      state = state.copyWith(
        isLoading: false,
        analytics: analytics,
        storeInfo: storeInfo,
      );
    } catch (e, st) {
      _log('load failed', e, st);
      state = state.copyWith(
        isLoading: false,
        error: 'Unable to load sales analytics. Please try again.',
      );
    }
  }

  void selectPeriod(ReportingPeriod period) {
    state = state.copyWith(
      period: period,
      clearCustomRange: period != ReportingPeriod.custom,
    );
    load();
  }

  void setCustomRange(DateTime start, DateTime end) {
    state = state.copyWith(
      period: ReportingPeriod.custom,
      customStart: start,
      customEnd: end,
    );
    load();
  }

  void refreshStoreInfo() async {
    try {
      final storeInfo = await _settingsService.getStoreInfo();
      state = state.copyWith(storeInfo: storeInfo);
    } catch (_) {
      // best-effort
    }
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[SalesAnalyticsNotifier] $message: $error\n$stackTrace');
    }
  }
}

final salesAnalyticsProvider =
    StateNotifierProvider<SalesAnalyticsNotifier, SalesAnalyticsState>((ref) {
  return SalesAnalyticsNotifier();
});
