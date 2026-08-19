import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';

/// Dashboard UI state. The UI matches on these three subtypes only — it
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

class DashboardLoaded extends DashboardState {
  final OwnerDashboardData? owner;
  final AdminDashboardData? admin;
  final StaffDashboardData? staff;

  const DashboardLoaded({this.owner, this.admin, this.staff});
}

/// Holds dashboard analytics state and triggers loads.
///
/// The notifier reads the current role from [SessionManager] (the single
/// source of truth for the authenticated user) and dispatches to the
/// role-scoped [DashboardService] method.  The service enforces RBAC and
/// role-based data filtering (e.g. Staff sees only own sales), so the
/// provider never has to interpret business data.
///
/// Lifecycle notes:
///   - `load()` is called once from the constructor to populate the
///     initial state.  This is safe because state is only set after an
///     `await`, never synchronously during construction.
///   - The UI calls `load()` again to refresh (pull-to-refresh / AppBar
///     refresh button).  No `ref.listen` is used in `initState`.
///   - On logout, [AuthProvider] invalidates this provider so the next
///     login starts with a fresh load.
class DashboardNotifier extends StateNotifier<DashboardState> {
  final DashboardService _service;
  final SessionManager _sessionManager;

  DashboardNotifier(this._service, this._sessionManager)
      : super(const DashboardLoading()) {
    load();
  }

  /// Reloads dashboard data for the current user. Sets [DashboardLoading]
  /// first so the UI can show skeletons, then replaces with the result.
  Future<void> load() async {
    state = const DashboardLoading();
    try {
      final role = _sessionManager.currentUser?.role;
      switch (role) {
        case UserRole.owner:
          final data = await _service.getOwnerDashboard();
          state = DashboardLoaded(owner: data);
        case UserRole.admin:
          final data = await _service.getAdminDashboard();
          state = DashboardLoaded(admin: data);
        case UserRole.staff:
          final data = await _service.getStaffDashboard();
          state = DashboardLoaded(staff: data);
        case null:
          state = const DashboardError('Not authenticated');
      }
    } catch (_) {
      state = const DashboardError(
        'Unable to load dashboard. Please try again.',
      );
    }
  }
}

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService();
});

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(
    ref.watch(dashboardServiceProvider),
    SessionManager(),
  );
});
