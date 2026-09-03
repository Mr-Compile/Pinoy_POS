import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/staff_service.dart';
import 'package:pinoy_pos/services/user_service.dart';

// ──────────────────────────────────────────────────────────────────────────
//  Staff List
// ──────────────────────────────────────────────────────────────────────────

/// Filter state for the staff management list.
enum StaffFilter {
  all,
  active,
  inactive,
}

/// State for the staff management list.
class StaffListState {
  final List<User> staff;
  final StaffFilter filter;
  final String searchQuery;
  final StaffSortOrder sortBy;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  const StaffListState({
    this.staff = const [],
    this.filter = StaffFilter.all,
    this.searchQuery = '',
    this.sortBy = StaffSortOrder.nameAsc,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  StaffListState copyWith({
    List<User>? staff,
    StaffFilter? filter,
    String? searchQuery,
    StaffSortOrder? sortBy,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return StaffListState(
      staff: staff ?? this.staff,
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final staffServiceProvider = Provider<StaffService>((ref) {
  return StaffService();
});

final staffControllerProvider =
    StateNotifierProvider<StaffController, StaffListState>((ref) {
  final staffService = ref.watch(staffServiceProvider);
  return StaffController(staffService);
});

class StaffController extends StateNotifier<StaffListState> {
  final StaffService _staffService;

  StaffController(this._staffService) : super(const StaffListState());

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  Future<void> loadStaff() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final activeOnly = switch (state.filter) {
        StaffFilter.all => null,
        StaffFilter.active => true,
        StaffFilter.inactive => false,
      };
      final staff = await _staffService.getStaff(
        search: state.searchQuery,
        sortBy: state.sortBy,
        activeOnly: activeOnly,
      );
      if (!mounted) return;
      state = state.copyWith(staff: staff, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: _friendlyError(e),
      );
    }
  }

  void setFilter(StaffFilter filter) {
    state = state.copyWith(filter: filter);
    loadStaff();
  }

  void setSearch(String query) {
    state = state.copyWith(searchQuery: query);
    loadStaff();
  }

  void setSort(StaffSortOrder sortBy) {
    state = state.copyWith(sortBy: sortBy);
    loadStaff();
  }

  Future<UserOperationResult> createStaff({
    required String username,
    required String fullName,
    String? pin,
  }) async {
    return _runMutation(
      () => _staffService.createStaff(
        username: username,
        fullName: fullName,
        pin: pin,
      ),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> updateStaff({
    required int staffId,
    String? username,
    String? fullName,
    String? pin,
  }) async {
    return _runMutation(
      () => _staffService.updateStaff(
        staffId: staffId,
        username: username,
        fullName: fullName,
        pin: pin,
      ),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> resetPassword(int staffId) async {
    return _runMutation(
      () => _staffService.resetStaffPassword(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> activateStaff(int staffId) async {
    return _runMutation(
      () => _staffService.activateStaff(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> deactivateStaff(int staffId) async {
    return _runMutation(
      () => _staffService.deactivateStaff(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> softDeleteStaff(int staffId) async {
    return _runMutation(
      () => _staffService.softDeleteStaff(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> restoreStaff(int staffId) async {
    return _runMutation(
      () => _staffService.restoreStaff(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> permanentlyDeleteStaff(int staffId) async {
    return _runMutation(
      () => _staffService.permanentlyDeleteStaff(staffId),
      onSuccess: loadStaff,
    );
  }

  Future<UserOperationResult> _runMutation(
    Future<UserOperationResult> Function() action, {
    Future<void> Function()? onSuccess,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final result = await action();
      if (result.success) {
        await onSuccess?.call();
      }
      if (!mounted) return UserOperationResult(success: false, message: 'Cancelled');
      state = state.copyWith(isSubmitting: false);
      return result;
    } catch (e) {
      if (!mounted) return UserOperationResult(success: false, message: 'Cancelled');
      final message = _friendlyError(e);
      state = state.copyWith(isSubmitting: false, error: message);
      return UserOperationResult(success: false, message: message);
    }
  }

  String _friendlyError(Object e) {
    if (e is AuthorizationException) {
      return e.message;
    }
    if (kDebugMode) {
      debugPrint('[StaffController] error: $e');
    }
    return 'An unexpected error occurred. Please try again.';
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Staff Detail
// ──────────────────────────────────────────────────────────────────────────

/// State for the staff detail / analytics screen.
class StaffDetailState {
  final User? staff;
  final SalesAnalytics? analytics;
  final List<ActivityLog> activityLogs;
  final Settings? storeInfo;
  final ReportingPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final bool isLoading;
  final String? error;

  const StaffDetailState({
    this.staff,
    this.analytics,
    this.activityLogs = const [],
    this.storeInfo,
    this.period = ReportingPeriod.thisMonth,
    this.customStart,
    this.customEnd,
    this.isLoading = false,
    this.error,
  });

  StaffDetailState copyWith({
    User? staff,
    SalesAnalytics? analytics,
    List<ActivityLog>? activityLogs,
    Settings? storeInfo,
    ReportingPeriod? period,
    DateTime? customStart,
    DateTime? customEnd,
    bool? isLoading,
    String? error,
    bool clearCustomRange = false,
    bool clearError = false,
    bool clearAnalytics = false,
  }) {
    return StaffDetailState(
      staff: staff ?? this.staff,
      analytics: clearAnalytics ? null : (analytics ?? this.analytics),
      activityLogs: activityLogs ?? this.activityLogs,
      storeInfo: storeInfo ?? this.storeInfo,
      period: period ?? this.period,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasCustomRange =>
      customStart != null &&
      customEnd != null &&
      period == ReportingPeriod.custom;
}

final staffDetailProvider = StateNotifierProvider.family<StaffDetailNotifier, StaffDetailState, int>(
  (ref, staffId) => StaffDetailNotifier(staffId),
);

class StaffDetailNotifier extends StateNotifier<StaffDetailState> {
  final int staffId;
  final StaffService _staffService;
  final SettingsService _settingsService;

  StaffDetailNotifier(this.staffId)
      : _staffService = StaffService(),
        _settingsService = SettingsService(),
        super(const StaffDetailState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true, clearAnalytics: true);
    try {
      final staff = await _staffService.getStaffById(staffId);
      if (staff == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Staff not found',
        );
        return;
      }

      final storeInfo = await _settingsService.getStoreInfo();
      final analytics = await _staffService.getStaffSalesAnalytics(
        staffId,
        state.period,
        customStart: state.customStart,
        customEnd: state.customEnd,
      );
      final activityLogs = await _staffService.getStaffActivityLogs(staffId);

      state = state.copyWith(
        isLoading: false,
        staff: staff,
        analytics: analytics,
        activityLogs: activityLogs,
        storeInfo: storeInfo,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _friendlyError(e),
      );
    }
  }

  Future<void> refreshStaff() async {
    try {
      final staff = await _staffService.getStaffById(staffId);
      state = state.copyWith(staff: staff);
    } catch (_) {
      // best-effort
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

  String _friendlyError(Object e) {
    if (e is AuthorizationException) {
      return e.message;
    }
    return 'An unexpected error occurred. Please try again.';
  }
}
