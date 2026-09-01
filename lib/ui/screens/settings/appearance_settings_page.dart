import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// Appearance settings sub-page — theme mode (system / light / dark).
///
/// Accessible from the Settings hub. Available to all authenticated
/// users (appearance is a personal preference, not role-restricted).
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return Scaffold(
      appBar: const AppHeader(title: 'Appearance', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Choose how the app looks. System follows your device setting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  _ThemeOption(
                    icon: Icons.brightness_auto_outlined,
                    title: 'System Default',
                    subtitle: 'Follow device setting',
                    isSelected: themeState.themeMode == 'system',
                    onTap: () => themeNotifier.setThemeMode('system'),
                  ),
                  const Divider(),
                  _ThemeOption(
                    icon: Icons.light_mode_outlined,
                    title: 'Light',
                    subtitle: 'Always light theme',
                    isSelected: themeState.themeMode == 'light',
                    onTap: () => themeNotifier.setThemeMode('light'),
                  ),
                  const Divider(),
                  _ThemeOption(
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark',
                    subtitle: 'Always dark theme',
                    isSelected: themeState.themeMode == 'dark',
                    onTap: () => themeNotifier.setThemeMode('dark'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppCard(
              child: ListTile(
                leading: Icon(Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Accent Color'),
                subtitle: const Text(
                    'Derived from the semantic primary color.'),
                trailing: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
      subtitle: Text(subtitle),
      trailing: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
