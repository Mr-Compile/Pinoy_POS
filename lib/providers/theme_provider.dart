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

  ThemeState({
    this.themeMode = 'system',
    this.accentColor = 'green',
  });

  ThemeState copyWith({
    String? themeMode,
    String? accentColor,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
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

  Future<void> setAccentColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent_color', color);
    state = state.copyWith(accentColor: color);
  }

  ThemeData getTheme(BuildContext context) {
    final brightness = switch (state.themeMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => MediaQuery.of(context).platformBrightness,
    };

    if (brightness == Brightness.dark) {
      return AppColors.getDarkTheme(state.accentColor);
    }
    return AppColors.getLightTheme(state.accentColor);
  }
}
