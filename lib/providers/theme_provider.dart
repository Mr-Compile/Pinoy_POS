import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinoy_pos/core/app_theme.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeState {
  /// Theme mode: 'system', 'light', or 'dark'.
  final String themeMode;

  /// The validated user accent color preference (authenticated app).
  /// Null when no user is authenticated.
  final String? userColorPreference;

  ThemeState({
    this.themeMode = 'system',
    this.userColorPreference,
  });

  /// Whether a user is currently authenticated (has a color preference).
  bool get isAuthenticated => userColorPreference != null;

  /// The accent color name to use for the authenticated application.
  /// Falls back to the default user accent if somehow null.
  String get authenticatedAccentColor =>
      AppColors.validateUserAccent(userColorPreference);

  ThemeState copyWith({
    String? themeMode,
    String? userColorPreference,
    bool clearUserColor = false,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      userColorPreference:
          clearUserColor ? null : (userColorPreference ?? this.userColorPreference),
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeMode = prefs.getString('theme') ?? 'system';
    state = ThemeState(themeMode: themeMode);
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', mode);
    state = state.copyWith(themeMode: mode);
  }

  /// Called when a user logs in or when a session is restored.
  /// Validates the preference and stores it in theme state.
  void syncUserColorPreference(String? colorPreference) {
    final validated = AppColors.validateUserAccent(colorPreference);
    state = state.copyWith(userColorPreference: validated);
  }

  /// Called when the current user changes their color preference.
  /// The preference should already be validated and persisted by the
  /// caller (AuthStateNotifier.updateProfile).
  void updateUserColorPreference(String colorPreference) {
    final validated = AppColors.validateUserAccent(colorPreference);
    state = state.copyWith(userColorPreference: validated);
  }

  /// Called on logout — clears the user-specific color preference so
  /// the application reverts to the Login (Blue) theme.
  void clearUserColorPreference() {
    state = state.copyWith(clearUserColor: true);
  }
}
