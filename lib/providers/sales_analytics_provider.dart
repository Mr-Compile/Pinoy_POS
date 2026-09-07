import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// UI state for the Sales Analytics / Reports screen.
class SalesAnalyticsState {
  final SalesAnalytics? analytics;
  final bool isLoading;
  final String? error;
  final Settings? storeInfo;
  final String? paymentMethod;
  final String? paymentStatus;

  const SalesAnalyticsState({
    this.analytics,
    this.isLoading = true,
    this.error,
    this.storeInfo,
    this.paymentMethod,
    this.paymentStatus = 'confirmed',
  });

  SalesAnalyticsState copyWith({
    SalesAnalytics? analytics,
    bool? isLoading,
    String? error,
    Settings? storeInfo,
    String? paymentMethod,
    String? paymentStatus,
    bool clearError = false,
    bool clearAnalytics = false,
    bool clearFilters = false,
  }) {
    return SalesAnalyticsState(
      analytics: clearAnalytics ? null : (analytics ?? this.analytics),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      storeInfo: storeInfo ?? this.storeInfo,
      paymentMethod: clearFilters ? null : (paymentMethod ?? this.paymentMethod),
      paymentStatus: clearFilters
          ? 'confirmed'
          : (paymentStatus ?? this.paymentStatus),
    );
  }

  bool get hasFilters =>
      (paymentMethod != null && paymentMethod!.isNotEmpty) ||
      (paymentStatus != null && paymentStatus != 'confirmed');
}

/// Notifier that loads role-scoped sales analytics for the selected period.
class SalesAnalyticsNotifier extends StateNotifier<SalesAnalyticsState> {
  final SalesAnalyticsService _service;
  final SettingsService _settingsService;
  final Ref _ref;

  SalesAnalyticsNotifier(this._ref)
      : _service = SalesAnalyticsService(),
        _settingsService = SettingsService(),
        super(const SalesAnalyticsState()) {
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearAnalytics: true,
    );
    try {
      final storeInfo = await _settingsService.getStoreInfo();
      if (!mounted) return;
      final filter = _ref.read(salesPeriodFilterProvider);
      final analytics = await _service.getAnalyticsForFilter(
        filter,
        paymentMethod: state.paymentMethod,
        paymentStatus: state.paymentStatus,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        analytics: analytics,
        storeInfo: storeInfo,
      );
    } catch (e, st) {
      _log('load failed', e, st);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Unable to load sales analytics. Please try again.',
      );
    }
  }

  void setPaymentMethod(String? method) {
    state = state.copyWith(paymentMethod: method);
    load();
  }

  void setPaymentStatus(String? status) {
    state = state.copyWith(paymentStatus: status);
    load();
  }

  void clearFilters() {
    state = state.copyWith(clearFilters: true);
    load();
  }

  void refreshStoreInfo() async {
    try {
      final storeInfo = await _settingsService.getStoreInfo();
      if (!mounted) return;
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
  return SalesAnalyticsNotifier(ref);
});
