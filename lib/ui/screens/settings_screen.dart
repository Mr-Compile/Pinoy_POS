import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final authNotifier = ref.read(authStateProvider.notifier);

    // Owner: edit_settings (business settings)
    // System Admin: backup_restore + edit_settings (system settings)
    final canEditBusiness = authNotifier.hasPermission('edit_settings') &&
        !authNotifier.hasPermission('backup_restore');
    final canEditSystem = authNotifier.hasPermission('edit_settings') &&
        authNotifier.hasPermission('backup_restore');
    final canBackup = authNotifier.hasPermission('backup_restore');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Appearance (all roles with view_settings) ---
          _SectionHeader(title: 'Appearance'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Theme Mode'),
                  subtitle: Text(themeState.themeMode.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showThemeDialog(context, themeNotifier, themeState.themeMode),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Accent Color'),
                  subtitle: Text(themeState.accentColor.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showColorDialog(context, themeNotifier, themeState.accentColor),
                ),
              ],
            ),
          ),

          // --- Business Settings (Owner only) ---
          if (canEditBusiness) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: 'Business Settings'),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Store Name'),
                    subtitle: const Text('Pinoy POS'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreName(context),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Store Address'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      'Store Address',
                      'store_address',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Store Contact'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      'Store Contact',
                      'store_phone',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Receipt Footer'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      'Receipt Footer',
                      'receipt_footer',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Currency'),
                    subtitle: const Text('Philippine Peso (₱)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showCurrencyDialog(context),
                  ),
                ],
              ),
            ),
          ],

          // --- System Settings (System Admin only) ---
          if (canEditSystem || canBackup) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: 'System Management'),
            if (canBackup)
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup),
                      title: const Text('Backup Data'),
                      subtitle: const Text('Create a database backup'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _createBackup(context),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Restore Data'),
                      subtitle: const Text('Restore from a backup file'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _restoreBackup(context),
                    ),
                  ],
                ),
              ),
            if (canEditSystem) ...[
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.policy),
                      title: const Text('User Policies'),
                      subtitle: const Text('Password rules, session timeout'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPlaceholderDialog(
                          context, 'User Policies'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.backup_table),
                      title: const Text('Backup Policies'),
                      subtitle: const Text('Auto-backup schedule, retention'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPlaceholderDialog(
                          context, 'Backup Policies'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.build),
                      title: const Text('Maintenance'),
                      subtitle: const Text('Database cleanup, logs purge'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPlaceholderDialog(
                          context, 'Maintenance'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editStoreName(BuildContext context) async {
    final settingsService = SettingsService();
    final settings = await settingsService.getSettings();
    if (!context.mounted) return;

    final controller = TextEditingController(text: settings.storeName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Store Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Store Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      await settingsService.updateSettings(settings.copyWith(storeName: result));
      if (context.mounted) {
        showSuccessSnackbar(context, 'Store name updated');
      }
    }
  }

  Future<void> _editStoreField(
    BuildContext context,
    String label,
    String fieldKey,
  ) async {
    final settingsService = SettingsService();
    final settings = await settingsService.getSettings();
    if (!context.mounted) return;

    String currentValue;
    switch (fieldKey) {
      case 'store_address':
        currentValue = settings.storeAddress;
        break;
      case 'store_phone':
        currentValue = settings.storePhone;
        break;
      case 'receipt_footer':
        currentValue = settings.receiptFooter ?? '';
        break;
      default:
        currentValue = '';
    }

    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: fieldKey == 'receipt_footer' ? 2 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && context.mounted) {
      final updated = settings.copyWith(
        storeAddress: fieldKey == 'store_address' ? result : null,
        storePhone: fieldKey == 'store_phone' ? result : null,
        receiptFooter: fieldKey == 'receipt_footer' ? result : null,
      );
      await settingsService.updateSettings(updated);
      if (context.mounted) {
        showSuccessSnackbar(context, '$label updated');
      }
    }
  }

  void _showCurrencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Currency'),
        content: const Text(
            'Philippine Peso (₱) is the only supported currency in this version.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPlaceholderDialog(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text('$title configuration will be available in a future update.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup(BuildContext context) async {
    final confirmed =
        await EnhancedDialogs.showRestoreBackupDialog(context: context);
    if (confirmed != true || !context.mounted) return;

    try {
      final backupService = BackupService();
      final path = await backupService.createBackup();
      if (context.mounted) {
        showSuccessSnackbar(context, 'Backup created: $path');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackbar(context, 'Failed to create backup');
      }
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final confirmed =
        await EnhancedDialogs.showRestoreBackupDialog(context: context);
    if (confirmed != true || !context.mounted) return;

    try {
      final backupService = BackupService();
      final dir = await backupService.createBackup();
      final success = await backupService.restoreBackup(dir);
      if (context.mounted) {
        if (success) {
          showSuccessSnackbar(
              context, 'Data restored successfully. Please restart the app.');
        } else {
          showErrorSnackbar(context, 'Failed to restore backup');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackbar(context, 'Failed to restore backup');
      }
    }
  }

  void _showThemeDialog(
      BuildContext context, ThemeNotifier notifier, String currentMode) {
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

  void _showColorDialog(
      BuildContext context, ThemeNotifier notifier, String currentColor) {
    final colors = ['green', 'blue', 'purple', 'orange', 'red'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accent Color'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: colors
              .map((color) => ListTile(
                    title: Text(color.toUpperCase()),
                    leading: _ColorSwatch(name: color, isSelected: color == currentColor),
                    onTap: () {
                      notifier.setAccentColor(color);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final bool isSelected;

  const _ColorSwatch({required this.name, required this.isSelected});

  Color _getColor() {
    return switch (name) {
      'green' => Colors.green,
      'blue' => Colors.blue,
      'purple' => Colors.purple,
      'orange' => Colors.orange,
      'red' => Colors.red,
      _ => Colors.green,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: _getColor(),
        shape: BoxShape.circle,
        border: isSelected
            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
            : null,
      ),
    );
  }
}
