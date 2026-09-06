import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/dashboard_provider.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/user_service.dart';

/// The phase of the authentication/session lifecycle.
///
/// This is the single source of truth for whether protected routes
/// are accessible.  Only [fullyAuthenticated] grants access to the
/// application shell and protected screens.
enum AuthSessionPhase {
  /// No user is authenticated.
  unauthenticated,

  /// Password login succeeded but the user’s temporary password must
  /// be changed before any further access is granted.
  passwordAuthenticatedPendingPasswordChange,

  /// Password login succeeded and the password is not temporary, but
  /// the user has a PIN configured.  The PIN lock screen must be shown
  /// and protected routes must remain inaccessible until the PIN is
  /// verified.
  passwordAuthenticatedPendingPin,

  /// Password (and PIN, if configured) are both verified, and the
  /// password is not a temporary one.  The user may access protected
  /// routes.
  fullyAuthenticated,
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthStateNotifier(ref, authService);
});

class AuthState {
  static const Object _sentinel = Object();

  final User? user;
  final bool isLoading;
  final String? error;
  final AuthSessionPhase phase;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.phase = AuthSessionPhase.unauthenticated,
  });

  AuthState copyWith({
    Object? user = _sentinel,
    bool? isLoading,
    String? error,
    AuthSessionPhase? phase,
  }) {
    return AuthState(
      user: user == _sentinel ? this.user : user as User?,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      phase: phase ?? this.phase,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  final AuthService _authService;

  AuthStateNotifier(this._ref, this._authService) : super(AuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    final status = await _authService.restoreSession();
    final user = _authService.currentUser;

    final phase = switch (status) {
      SessionStatus.none || SessionStatus.expired => AuthSessionPhase.unauthenticated,
      SessionStatus.locked => user != null && user.hasPin
          ? AuthSessionPhase.passwordAuthenticatedPendingPin
          : AuthSessionPhase.unauthenticated,
      SessionStatus.active => _resolveActivePhase(user!),
    };

    state = state.copyWith(
      user: status == SessionStatus.none || status == SessionStatus.expired
          ? null
          : user,
      isLoading: false,
      phase: phase,
    );
  }

  AuthSessionPhase _resolveActivePhase(User user) {
    if (user.mustChangePassword) {
      return AuthSessionPhase.passwordAuthenticatedPendingPasswordChange;
    }
    if (user.hasPin) {
      final pinVerified = _authService.currentSessionMetadata?.pinVerified ?? false;
      return pinVerified
          ? AuthSessionPhase.fullyAuthenticated
          : AuthSessionPhase.passwordAuthenticatedPendingPin;
    }
    return AuthSessionPhase.fullyAuthenticated;
  }

  Future<LoginResult> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _authService.login(username, password);
    switch (result) {
      case LoginResult.success:
        final user = _authService.currentUser!;
        final AuthSessionPhase phase;
        if (user.mustChangePassword) {
          phase = AuthSessionPhase.passwordAuthenticatedPendingPasswordChange;
        } else if (_authService.currentUserHasPin) {
          phase = AuthSessionPhase.passwordAuthenticatedPendingPin;
        } else {
          phase = AuthSessionPhase.fullyAuthenticated;
        }
        state = state.copyWith(
          user: user,
          isLoading: false,
          phase: phase,
        );
        // Invalidate providers that hold per-user cached state so they
        // reload with the new user’s data.  Without this, the dashboard
        // and notification badge show stale data (or the "Not
        // authenticated" error left over from the previous logout).
        // Container-level: `dashboardProvider` watches `authStateProvider`,
        // so element-level `_ref.invalidate` throws CircularDependencyError.
        _ref.container.invalidate(dashboardProvider);
        _ref.container.invalidate(notificationCountProvider);
      case LoginResult.invalidCredentials:
        state = state.copyWith(isLoading: false, error: 'Username or password is incorrect.');
      case LoginResult.inactiveAccount:
        state = state.copyWith(isLoading: false, error: 'Your account is currently inactive. Please contact an administrator.');
      case LoginResult.error:
        state = state.copyWith(isLoading: false, error: 'Unable to sign in right now. Please try again.');
    }
    return result;
  }

  Future<bool> loginWithPin(String username, String pin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _authService.loginWithPin(username, pin);
      if (success) {
        state = state.copyWith(
          user: _authService.currentUser,
          isLoading: false,
          phase: AuthSessionPhase.fullyAuthenticated,
        );
        // Reload per-user cached state for the new session.
        _ref.container.invalidate(dashboardProvider);
        _ref.container.invalidate(notificationCountProvider);
      } else {
        state = state.copyWith(isLoading: false, error: 'Incorrect username or PIN.');
      }
      return success;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Unable to sign in right now. Please try again.');
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    // Reset the auth state BEFORE invalidating cached providers. Any
    // provider that recreates itself during invalidation must observe a
    // fully cleared session (user == null, phase == unauthenticated);
    // doing this after the invalidation would leave them reading a
    // half-torn-down state where AuthState still holds the old user while
    // the SessionManager singleton has already been cleared.
    state = AuthState();
    _invalidateAllCachedProviders();
  }

  /// Transitions a fully authenticated session to the PIN-locked state.
  ///
  /// Called by the session timeout when the inactivity window expires.  If
  /// the user does not have a PIN, this performs a full logout instead.
  Future<void> lockSession() async {
    final user = state.user;
    if (user == null) return;
    if (user.hasPin) {
      state = state.copyWith(
        phase: AuthSessionPhase.passwordAuthenticatedPendingPin,
        error: null,
      );
      await _authService.setPinVerified(false);
      return;
    }
    await logout();
  }

  /// Changes the current user’s password during the forced first-login
  /// flow.  Does not require the old password.  On success, transitions
  /// to the PIN phase (if configured) or fully authenticated.
  ///
  /// Returns a [UserOperationResult] from the user service.
  Future<UserOperationResult> changePassword({
    required String newPassword,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      return UserOperationResult(
        success: false,
        message: 'No active session',
      );
    }

    final result = await _ref
        .read(userControllerProvider.notifier)
        .forceChangePassword(
      userId: user.id!,
      newPassword: newPassword,
    );

    if (result.success) {
      // Refresh the current user from DB to get updated state.
      await _authService.refreshCurrentUser();
      final updatedUser = _authService.currentUser!;

      final AuthSessionPhase phase;
      if (updatedUser.mustChangePassword) {
        phase = AuthSessionPhase.passwordAuthenticatedPendingPasswordChange;
      } else if (updatedUser.hasPin) {
        phase = AuthSessionPhase.passwordAuthenticatedPendingPin;
      } else {
        phase = AuthSessionPhase.fullyAuthenticated;
      }

      state = state.copyWith(
        user: updatedUser,
        phase: phase,
        error: null,
      );
      await _authService.setPinVerified(phase == AuthSessionPhase.fullyAuthenticated);
      // Reload per-user cached state after password change.
      _ref.container.invalidate(dashboardProvider);
      _ref.container.invalidate(notificationCountProvider);
    }
    return result;
  }

  /// Verifies the PIN for the post-login PIN lock flow.
  /// Returns a [PinVerifyResult] from the auth service.
  /// On success, transitions to [AuthSessionPhase.fullyAuthenticated].
  Future<PinVerifyResult> verifyPin(String pin) async {
    final result = await _authService.verifyPin(pin);
    if (result == PinVerifyResult.success) {
      state = state.copyWith(
        user: _authService.currentUser,
        phase: AuthSessionPhase.fullyAuthenticated,
        error: null,
      );
      // Reload per-user cached state after PIN verification.
      _ref.container.invalidate(dashboardProvider);
      _ref.container.invalidate(notificationCountProvider);
    }
    return result;
  }

  /// Cancels the PIN lock flow and returns to the login screen.
  /// Clears all temporary authentication/session state.
  Future<void> cancelPinFlow() async {
    await _authService.logout();
    // See [logout]: the auth state is cleared before cached providers are
    // invalidated so they never observe a partially torn-down session.
    state = AuthState();
    _invalidateAllCachedProviders();
  }

  /// Discards cached state tied to the current user. Called by [logout]
  /// and [cancelPinFlow] so the next session starts with fresh providers.
  ///
  /// Invalidation goes through [ProviderContainer.invalidate] rather than
  /// [Ref.invalidate]: several of these providers (e.g. `dashboardProvider`)
  /// `watch` `authStateProvider`, and the element-level `ref.invalidate`
  /// throws `CircularDependencyError` for targets that depend on this
  /// element. In debug builds that throw aborted logout before the auth
  /// state was cleared. Container-level invalidation performs the same
  /// invalidate without the caller-dependency check — this is safe here
  /// because the relationship is one-way (dashboard watches auth; auth
  /// never reads dashboard).
  void _invalidateAllCachedProviders() {
    final container = _ref.container;
    container.invalidate(productServiceProvider);
    container.invalidate(categoryServiceProvider);
    container.invalidate(salesServiceProvider);
    container.invalidate(stockServiceProvider);
    container.invalidate(activityLogServiceProvider);
    container.invalidate(notificationServiceProvider);
    container.invalidate(notificationCountProvider);
    container.invalidate(settingsServiceProvider);
    container.invalidate(reportServiceProvider);
    container.invalidate(backupServiceProvider);
    container.invalidate(aiUsageServiceProvider);
    container.invalidate(aiAdvisorServiceProvider);
    container.invalidate(aiAdvisorChatProvider);
    container.invalidate(groqServiceProvider);
    container.invalidate(trashServiceProvider);
    container.invalidate(announcementServiceProvider);
    container.invalidate(userServiceProvider);
    container.invalidate(userControllerProvider);
    container.invalidate(dashboardProvider);
    container.invalidate(cartProvider);
  }

  /// Called after the current user’s own record is edited (e.g. by
  /// UserController.updateUser) so that the session reflects the latest
  /// database state without causing a circular dependency.
  Future<void> refreshCurrentUser() async {
    await _authService.refreshCurrentUser();
    state = state.copyWith(user: _authService.currentUser);
  }

  User? get currentUser => state.user;

  bool hasPermission(String permission) {
    return _authService.hasPermission(permission);
  }

  void refreshUser() {
    state = state.copyWith(user: _authService.currentUser);
  }

  /// Updates the current user’s own profile (full name, username, PIN,
  /// profile image). No special permission is required — users can always
  /// edit their own profile. Restricted fields (role, isActive) are never
  /// modified here.
  ///
  /// Returns true on success, false on failure.
  Future<bool> updateProfile({
    required int userId,
    required String fullName,
    String? username,
    String? pin,
    String? profileImagePath,
  }) async {
    final success = await _authService.updateProfile(
      userId: userId,
      fullName: fullName,
      username: username,
      pin: pin,
      profileImagePath: profileImagePath,
    );
    if (success) {
      state = state.copyWith(user: _authService.currentUser);
    }
    return success;
  }
}
