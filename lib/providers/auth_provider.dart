import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/data/models/user.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthStateNotifier(authService);
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

  AuthStateNotifier(this._authService) : super(AuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    final restored = await _authService.restoreSession();
    if (restored) {
      state = state.copyWith(user: _authService.currentUser, isLoading: false);
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    final success = await _authService.login(username, password);
    if (success) {
      state = state.copyWith(user: _authService.currentUser, isLoading: false);
    } else {
      state = state.copyWith(isLoading: false, error: 'Invalid credentials');
    }
    return success;
  }

  Future<bool> loginWithPin(String username, String pin) async {
    state = state.copyWith(isLoading: true, error: null);
    final success = await _authService.loginWithPin(username, pin);
    if (success) {
      state = state.copyWith(user: _authService.currentUser, isLoading: false);
    } else {
      state = state.copyWith(isLoading: false, error: 'Invalid PIN');
    }
    return success;
  }

  Future<void> logout() async {
    await _authService.logout();
    state = state.copyWith(user: null);
  }

  bool hasPermission(String permission) {
    return _authService.hasPermission(permission);
  }
}
