import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';

/// Dashboard UI state. The UI matches on these four subtypes only - it
/// never computes analytics itself.
sealed class DashboardState {
  const DashboardState();
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError(this.message);
}

/// The current user is authenticated but lacks `view_dashboard`.
/// Kept separate from [DashboardError] so a denied user sees an
/// access-denied view instead of a misleading "Not authenticated" error.
class DashboardDenied extends DashboardState {
  const DashboardDenied();
}

class DashboardLoaded extends DashboardState {
  /// The role-scoped payload produced by [DashboardService.getDashboard].
  /// The UI switches on the concrete [DashboardData] subtype, which is
  /// guaranteed to match the role the service loaded for.
  final DashboardData data;

  const DashboardLoaded({required this.data});
}

/// Holds dashboard analytics state and triggers loads.
///
/// The service enforces RBAC and role-based data filtering (e.g. Staff sees
/// only own sales), so the provider never has to interpret business data.
///
/// The selected [SalesPeriodFilter] is read from [salesPeriodFilterProvider]
/// so the Dashboard and Sales Analytics screens share the same period rules.
class DashboardNotifier extends StateNotifier<DashboardState> {
  final DashboardService _service;
  final Ref _ref;

  /// Whether a user is signed in. Used to distinguish "no session" from
  /// "authenticated but denied" when the service returns null.
  final bool isAuthenticated;

  DashboardNotifier(this._service, this._ref, {required this.isAuthenticated})
      : super(const DashboardLoading()) {
    load();
  }

  /// Reloads dashboard data for the current user and selected period.
  Future<void> load() async {
    state = const DashboardLoading();
    try {
      final filter = _ref.read(salesPeriodFilterProvider);
      final data = await _service.getDashboard(filter);
      if (!mounted) return;
      if (data == null) {
        // The service returns null for two distinct cases: no session
        // (unauthenticated) and an authenticated user without
        // `view_dashboard` (denied). Surface them differently.
        state = isAuthenticated ? const DashboardDenied() : const DashboardError('Not authenticated');
      } else {
        state = DashboardLoaded(data: data);
      }
    } catch (_) {
      if (!mounted) return;
      state = const DashboardError('Unable to load dashboard. Please try again.');
    }
  }
}

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService();
});

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  // Watching the signed-in flag recreates the notifier on login/logout/
  // account switch, so the dashboard reloads for the new user instead of
  // serving the previous role's cached state.
  final isAuthenticated =
      ref.watch(authStateProvider.select((s) => s.user != null));

  final notifier = DashboardNotifier(
    ref.watch(dashboardServiceProvider),
    ref,
    isAuthenticated: isAuthenticated,
  );

  // Reload the dashboard whenever the shared sales period filter changes.
  // Keeping the listener at the provider level ensures the dashboard state is
  // refreshed even when the Dashboard screen is not currently in the widget
  // tree (e.g. the filter was changed from the Sales Analytics screen and the
  // user then returns to the Dashboard).
  ref.listen(salesPeriodFilterProvider, (previous, next) {
    notifier.load();
  });

  return notifier;
});
