import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
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

class DashboardLoaded extends DashboardState {
  final OwnerDashboardData? owner;
  final AdminDashboardData? admin;
  final StaffDashboardData? staff;

  const DashboardLoaded({
    super.period,
    super.customStart,
    super.customEnd,
    this.owner,
    this.admin,
    this.staff,
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

  DashboardNotifier(this._service)
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
      final data = await _service.getDashboard();
      switch (data) {
        case OwnerDashboardData():
          state = DashboardLoaded(
            period: current.period,
            customStart: current.customStart,
            customEnd: current.customEnd,
            owner: data,
          );
        case AdminDashboardData():
          state = DashboardLoaded(
            period: current.period,
            customStart: current.customStart,
            customEnd: current.customEnd,
            admin: data,
          );
        case StaffDashboardData():
          state = DashboardLoaded(
            period: current.period,
            customStart: current.customStart,
            customEnd: current.customEnd,
            staff: data,
          );
        case null:
          state = DashboardError(
            'Not authenticated',
            period: current.period,
            customStart: current.customStart,
            customEnd: current.customEnd,
          );
      }
    } catch (_) {
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
  return DashboardNotifier(
    ref.watch(dashboardServiceProvider),
  );
});
