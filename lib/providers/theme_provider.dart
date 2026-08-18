import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinoy_pos/core/app_theme.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeState {
  final String themeMode;
  final String accentColor;
  final String? userColorPreference;

  ThemeState({
    this.themeMode = 'system',
    this.accentColor = 'green',
    this.userColorPreference,
  });

  /// The effective accent color: user preference if authenticated, else global setting.
  String get effectiveAccentColor => userColorPreference ?? accentColor;

  ThemeState copyWith({
    String? themeMode,
    String? accentColor,
    String? userColorPreference,
    bool clearUserColor = false,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      userColorPreference: clearUserColor ? null : (userColorPreference ?? this.userColorPreference),
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
    final accentColor = prefs.getString('accent_color') ?? 'green';
    state = ThemeState(
      themeMode: themeMode,
      accentColor: accentColor,
    );
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', mode);
    state = state.copyWith(themeMode: mode);
  }

  /// Set the global default accent color (used when no user is authenticated).
  Future<void> setAccentColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent_color', color);
    state = state.copyWith(accentColor: color);
  }

  /// Called when a user logs in — loads their personal color preference.
  void syncUserColorPreference(String? colorPreference) {
    state = state.copyWith(userColorPreference: colorPreference);
  }

  /// Called when the current user changes their color preference.
  void updateUserColorPreference(String colorPreference) {
    state = state.copyWith(userColorPreference: colorPreference);
  }

  /// Called on logout — clears user-specific color, reverts to global default.
  void clearUserColorPreference() {
    state = state.copyWith(clearUserColor: true);
  }

  ThemeData getTheme(BuildContext context) {
    final brightness = switch (state.themeMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => MediaQuery.of(context).platformBrightness,
    };

    final effectiveColor = state.effectiveAccentColor;

    if (brightness == Brightness.dark) {
      return AppColors.getDarkTheme(effectiveColor);
    }
    return AppColors.getLightTheme(effectiveColor);
  }
}