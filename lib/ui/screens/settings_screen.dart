import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Theme Mode'),
                  subtitle: Text(themeState.themeMode.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemeDialog(context, themeNotifier, themeState.themeMode),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Accent Color'),
                  subtitle: Text(themeState.accentColor.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showColorDialog(context, themeNotifier, themeState.accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Business Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: ListTile(
              title: const Text('Store Name'),
              subtitle: const Text('Pinoy POS'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: ListTile(
              title: const Text('Currency'),
              subtitle: const Text('Philippine Peso (₱)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Data',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Backup Data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore Data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, ThemeNotifier notifier, String currentMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme Mode'),
        content: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'system',
              label: Text('System'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: 'light',
              label: Text('Light'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: 'dark',
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {currentMode},
          onSelectionChanged: (Set<String> newSelection) {
            notifier.setThemeMode(newSelection.first);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showColorDialog(BuildContext context, ThemeNotifier notifier, String currentColor) {
    final colors = ['green', 'blue', 'purple', 'orange', 'red'];
    final colorIcons = {
      'green': Icons.circle,
      'blue': Icons.circle,
      'purple': Icons.circle,
      'orange': Icons.circle,
      'red': Icons.circle,
    };
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accent Color'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: colors.map((color) => ListTile(
            title: Text(color.toUpperCase()),
            leading: Icon(colorIcons[color]),
            onTap: () {
              notifier.setAccentColor(color);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }
}
