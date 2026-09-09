import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// Appearance settings sub-page — theme mode (light / dark only).
///
/// Accessible from the Settings hub. Available to all authenticated
/// users (appearance is a personal preference, not role-restricted).
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: const AppHeader(title: 'Appearance', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how the app looks.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  _ThemeOption(
                    icon: Icons.light_mode,
                    title: 'Light',
                    subtitle: 'Always light theme',
                    color: AppSemanticColors.resolve(
                      AppSemanticColors.warning,
                      brightness,
                    ),
                    isSelected: themeState.themeMode == 'light',
                    onTap: () => themeNotifier.setThemeMode('light'),
                  ),
                  const Divider(height: 1),
                  _ThemeOption(
                    icon: Icons.dark_mode,
                    title: 'Dark',
                    subtitle: 'Always dark theme',
                    color: AppSemanticColors.resolve(
                      AppSemanticColors.info,
                      brightness,
                    ),
                    isSelected: themeState.themeMode == 'dark',
                    onTap: () => themeNotifier.setThemeMode('dark'),
                  ),
                ],
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
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.icon),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? color : cs.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
