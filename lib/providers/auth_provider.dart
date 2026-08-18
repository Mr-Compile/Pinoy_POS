import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final themeNotifier = ref.watch(themeProvider.notifier);
  return AuthStateNotifier(authService, themeNotifier);
});

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final ThemeNotifier _themeNotifier;

  AuthStateNotifier(this._authService, this._themeNotifier) : super(AuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    final restored = await _authService.restoreSession();
    if (restored) {
      state = state.copyWith(user: _authService.currentUser, isLoading: false);
      _themeNotifier.syncUserColorPreference(_authService.currentUser?.colorPreference);
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _authService.login(username, password);
      if (success) {
        state = state.copyWith(user: _authService.currentUser, isLoading: false);
        _themeNotifier.syncUserColorPreference(_authService.currentUser?.colorPreference);
      } else {
        state = state.copyWith(isLoading: false, error: 'Incorrect username or password.');
      }
      return success;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Unable to sign in right now. Please try again.');
      return false;
    }
  }

  Future<bool> loginWithPin(String username, String pin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _authService.loginWithPin(username, pin);
      if (success) {
        state = state.copyWith(user: _authService.currentUser, isLoading: false);
        _themeNotifier.syncUserColorPreference(_authService.currentUser?.colorPreference);
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
    _themeNotifier.clearUserColorPreference();
    state = state.copyWith(user: null);
  }

  /// Reloads the current user from the database and updates the auth state.
  /// Called after the current user's own record is edited (e.g. by
  /// UserController.updateUser) so that the session reflects the latest
  /// database state without causing a circular dependency.
  Future<void> refreshCurrentUser() async {
    await _authService.refreshCurrentUser();
    state = state.copyWith(user: _authService.currentUser);
  }

  bool hasPermission(String permission) {
    return _authService.hasPermission(permission);
  }

  void refreshUser() {
    state = state.copyWith(user: _authService.currentUser);
    _themeNotifier.syncUserColorPreference(_authService.currentUser?.colorPreference);
  }

  /// Updates the current user's own profile (full name, PIN, color
  /// preference). No special permission is required — users can always
  /// edit their own profile. Restricted fields (role, username, isActive)
  /// are never modified here.
  ///
  /// Returns true on success, false on failure.
  Future<bool> updateProfile({
    required int userId,
    required String fullName,
    String? pin,
    String? colorPreference,
  }) async {
    final success = await _authService.updateProfile(
      userId: userId,
      fullName: fullName,
      pin: pin,
      colorPreference: colorPreference,
    );
    if (success) {
      state = state.copyWith(user: _authService.currentUser);
      _themeNotifier.syncUserColorPreference(_authService.currentUser?.colorPreference);
    }
    return success;
  }
}
