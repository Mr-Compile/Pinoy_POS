import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

/// The application supports only Light and Dark modes. The legacy 'system'
/// value is migrated to 'light' on first load.
class ThemeState {
  /// Theme mode: 'light' or 'dark'.
  final String themeMode;

  ThemeState({
    this.themeMode = 'light',
  });

  ThemeState copyWith({
    String? themeMode,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
    );
  }

  bool get isLight => themeMode == 'light';
  bool get isDark => themeMode == 'dark';
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  static const _key = 'theme';

  ThemeNotifier() : super(ThemeState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString(_key) ?? 'light';

    // Migrate any persisted 'system' value from a previous version.
    if (stored == 'system') {
      stored = 'light';
      await prefs.setString(_key, stored);
    }

    state = ThemeState(themeMode: _validated(stored));
  }

  Future<void> setThemeMode(String mode) async {
    final validated = _validated(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, validated);
    state = state.copyWith(themeMode: validated);
  }

  /// Cycles light -> dark -> light.
  void toggle() {
    final next = state.isLight ? 'dark' : 'light';
    setThemeMode(next);
  }

  String _validated(String mode) {
    return (mode == 'light' || mode == 'dark') ? mode : 'light';
  }
}
