import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';

/// Theme mode toggle that cycles through system, light, and dark.
///
/// Displays the current mode as a subtle icon button. Tapping it
/// advances to the next mode and persists the choice via [themeProvider].
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    final (icon, label) = switch (themeState.themeMode) {
      'light' => (Icons.light_mode_outlined, 'Light'),
      'dark' => (Icons.dark_mode_outlined, 'Dark'),
      _ => (Icons.brightness_auto_outlined, 'System'),
    };

    return Tooltip(
      message: 'Theme: $label. Tap to change.',
      child: IconButton(
        onPressed: () {
          final next = switch (themeState.themeMode) {
            'system' => 'light',
            'light' => 'dark',
            _ => 'system',
          };
          themeNotifier.setThemeMode(next);
        },
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
