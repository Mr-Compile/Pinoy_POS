import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';

/// Dashboard UI state. The UI matches on these three subtypes only - it
/// never computes analytics itself.
sealed class DashboardState {
  final ReportingPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;

  const DashboardState({
    this.period = ReportingPeriod.today,
    this.customStart,
    this.customEnd,
  });

  bool get hasCustomRange =>
      customStart != null && customEnd != null && period == ReportingPeriod.custom;
}

class DashboardLoading extends DashboardState {
  const DashboardLoading({
    super.period,
    super.customStart,
    super.customEnd,
  });
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError(
    this.message, {
    super.period,
    super.customStart,
    super.customEnd,
  });
}

/// The current user is authenticated but lacks `view_dashboard`.
/// Kept separate from [DashboardError] so a denied user sees an
/// access-denied view instead of a misleading "Not authenticated" error.
class DashboardDenied extends DashboardState {
  const DashboardDenied({
    super.period,
    super.customStart,
    super.customEnd,
  });
}

class DashboardLoaded extends DashboardState {
  /// The role-scoped payload produced by [DashboardService.getDashboard].
  /// The UI switches on the concrete [DashboardData] subtype, which is
  /// guaranteed to match the role the service loaded for.
  final DashboardData data;

  const DashboardLoaded({
    required this.data,
    super.period,
    super.customStart,
    super.customEnd,
  });
}

/// Holds dashboard analytics state and triggers loads.
///
/// The service enforces RBAC and role-based data filtering (e.g. Staff sees
/// only own sales), so the provider never has to interpret business data.
///
/// The selected [ReportingPeriod] and optional custom range are part of the
/// state so the UI can keep the date filter in sync while data reloads.
class DashboardNotifier extends StateNotifier<DashboardState> {
  final DashboardService _service;

  /// Whether a user is signed in. Used to distinguish "no session" from
  /// "authenticated but denied" when the service returns null.
  final bool isAuthenticated;

  DashboardNotifier(this._service, {required this.isAuthenticated})
      : super(const DashboardLoading()) {
    load();
  }

  /// Reloads dashboard data for the current user and selected period.
  Future<void> load() async {
    final current = state;
    state = DashboardLoading(
      period: current.period,
      customStart: current.customStart,
      customEnd: current.customEnd,
    );
    try {
      final data = await _service.getDashboard(
        current.period,
        customStart: current.customStart,
        customEnd: current.customEnd,
      );
      if (!mounted) return;
      if (data == null) {
        // The service returns null for two distinct cases: no session
        // (unauthenticated) and an authenticated user without
        // `view_dashboard` (denied). Surface them differently.
        state = isAuthenticated
            ? DashboardDenied(
                period: current.period,
                customStart: current.customStart,
                customEnd: current.customEnd,
              )
            : DashboardError(
                'Not authenticated',
                period: current.period,
                customStart: current.customStart,
                customEnd: current.customEnd,
              );
      } else {
        state = DashboardLoaded(
          data: data,
          period: current.period,
          customStart: current.customStart,
          customEnd: current.customEnd,
        );
      }
    } catch (_) {
      if (!mounted) return;
      state = DashboardError(
        'Unable to load dashboard. Please try again.',
        period: current.period,
        customStart: current.customStart,
        customEnd: current.customEnd,
      );
    }
  }

  /// Selects a preset [period] and reloads dashboard data.
  Future<void> selectPeriod(ReportingPeriod period) async {
    state = DashboardLoading(
      period: period,
      customStart: null,
      customEnd: null,
    );
    await load();
  }

  /// Sets a custom [DateTimeRange] and reloads dashboard data.
  Future<void> setCustomRange(DateTime start, DateTime end) async {
    state = DashboardLoading(
      period: ReportingPeriod.custom,
      customStart: start,
      customEnd: end,
    );
    await load();
  }
}

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService();
});

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  // Watching the signed-in flag recreates the notifier on login/logout/
  // account switch, so the dashboard reloads for the new user instead of
  // serving the previous user's cached state.
  final isAuthenticated =
      ref.watch(authStateProvider.select((s) => s.user != null));
  return DashboardNotifier(
    ref.watch(dashboardServiceProvider),
    isAuthenticated: isAuthenticated,
  );
});
