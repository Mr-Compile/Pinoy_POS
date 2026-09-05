import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/user_service.dart';

// ──────────────────────────────────────────────────────────────────────────
//  State
// ──────────────────────────────────────────────────────────────────────────

/// State for the User Management list.
class UserListState {
  final List<User> users;
  final List<User> deletedUsers;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  const UserListState({
    this.users = const [],
    this.deletedUsers = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  UserListState copyWith({
    List<User>? users,
    List<User>? deletedUsers,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
  }) {
    return UserListState(
      users: users ?? this.users,
      deletedUsers: deletedUsers ?? this.deletedUsers,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Controller
// ──────────────────────────────────────────────────────────────────────────

/// Controller for User Management CRUD.
///
/// The UI interacts exclusively with this controller (via
/// [userControllerProvider]); it never touches the service, repository, or
/// DAO directly.
///
/// After every successful mutation the controller reloads the user list
/// from SQLite so that the UI always reflects the persisted database
/// state.
///
/// Dependency graph (no cycle):
///   userControllerProvider
///     → userServiceProvider → UserService → (Repo, DAO, SQLite)
///     → authStateProvider.notifier (read-only, for session refresh)
final userControllerProvider =
    StateNotifierProvider<UserController, UserListState>((ref) {
  final userService = ref.watch(userServiceProvider);
  return UserController(ref, userService);
});

class UserController extends StateNotifier<UserListState> {
  final Ref _ref;
  final UserService _userService;

  UserController(this._ref, this._userService) : super(const UserListState());

  /// Clears any previous error so a stale message is not shown to the user.
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  /// Loads both active and deleted users from SQLite.
  Future<void> loadUsers() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final users = await _userService.getAllUsers();
      final deletedUsers = await _userService.getDeletedUsers();
      state = state.copyWith(
        users: users,
        deletedUsers: deletedUsers,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _friendlyError(e),
      );
    }
  }

  /// Loads only deleted users (for Trash).
  Future<void> loadDeletedUsers() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final deletedUsers = await _userService.getDeletedUsers();
      state = state.copyWith(deletedUsers: deletedUsers, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  // ── CREATE ───────────────────────────────────────────

  Future<UserOperationResult> createUser({
    required String username,
    required String fullName,
    required UserRole role,
    String? pin,
    int? inactivityTimeoutMinutes,
  }) {
    return _runMutation(
      () => _userService.createUser(
        username: username,
        fullName: fullName,
        role: role,
        pin: pin,
        inactivityTimeoutMinutes: inactivityTimeoutMinutes,
      ),
      onSuccess: loadUsers,
    );
  }

  // ── UPDATE ───────────────────────────────────────────

  Future<UserOperationResult> updateUser({
    required int userId,
    String? username,
    String? fullName,
    UserRole? role,
    String? pin,
    Object? inactivityTimeoutMinutes = User.inactivityTimeoutSentinel,
  }) {
    return _runMutation(
      () => _userService.updateUser(
        userId: userId,
        username: username,
        fullName: fullName,
        role: role,
        pin: pin,
        inactivityTimeoutMinutes: inactivityTimeoutMinutes,
      ),
      onSuccess: () async {
        await loadUsers();
        // Refresh the auth session if the current user edited themselves.
        await _ref.read(authStateProvider.notifier).refreshCurrentUser();
      },
    );
  }

  // ── PASSWORD ─────────────────────────────────────────

  Future<UserOperationResult> forceChangePassword({
    required int userId,
    required String newPassword,
  }) {
    return _runMutation(
      () => _userService.forceChangePassword(
        userId: userId,
        newPassword: newPassword,
      ),
    );
  }

  Future<UserOperationResult> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) {
    return _runMutation(
      () => _userService.changePassword(
        userId: userId,
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
    );
  }

  Future<UserOperationResult> resetPassword(int userId) {
    return _runMutation(() => _userService.resetPassword(userId));
  }

  // ── ACTIVATE / DEACTIVATE ────────────────────────────

  Future<UserOperationResult> activateUser(int userId) {
    return _runMutation(
      () => _userService.activateUser(userId),
      onSuccess: loadUsers,
    );
  }

  Future<UserOperationResult> deactivateUser(int userId) {
    return _runMutation(
      () => _userService.deactivateUser(userId),
      onSuccess: loadUsers,
    );
  }

  // ── SOFT DELETE ──────────────────────────────────────

  Future<UserOperationResult> softDeleteUser(int userId) {
    return _runMutation(
      () => _userService.softDeleteUser(userId),
      onSuccess: loadUsers,
    );
  }

  // ── RESTORE ──────────────────────────────────────────

  Future<UserOperationResult> restoreUser(int userId) {
    return _runMutation(
      () => _userService.restoreUser(userId),
      onSuccess: loadUsers,
    );
  }

  // ── PERMANENT DELETE ─────────────────────────────────

  Future<UserOperationResult> permanentlyDeleteUser(int userId) {
    return _runMutation(
      () => _userService.permanentlyDeleteUser(userId),
      onSuccess: loadUsers,
    );
  }

  /// Runs a [UserOperationResult] mutation with the standard
  /// `isSubmitting` / `error` boilerplate. When [onSuccess] is provided
  /// and the mutation succeeds, it is awaited after the service call.
  Future<UserOperationResult> _runMutation(
    Future<UserOperationResult> Function() action, {
    Future<void> Function()? onSuccess,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final result = await action();
      if (result.success) {
        await onSuccess?.call();
      }
      state = state.copyWith(isSubmitting: false);
      return result;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: _friendlyError(e));
      return UserOperationResult(success: false, message: _friendlyError(e));
    }
  }

  /// Converts low-level exceptions into a user-friendly message.
  String _friendlyError(Object e) {
    if (e is AuthorizationException) {
      return e.message;
    }
    return 'An unexpected error occurred. Please try again.';
  }
}
