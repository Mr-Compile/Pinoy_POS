import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Settings? _settings;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final settingsService = ref.read(settingsServiceProvider);
      final settings = await settingsService.getSettings();
      if (context.mounted) {
        setState(() {
          _settings = settings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load settings. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ErrorState(
          title: 'Failed to Load Settings',
          message: _loadError,
          onRetry: _loadSettings,
        ),
      );
    }

    final settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
            tooltip: 'Refresh',
          ),
        ],
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
                  subtitle: Text(themeState.authenticatedAccentColor.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showColorDialog(context, themeNotifier, themeState.authenticatedAccentColor),
                ),
              ],
            ),
          ),

          // --- Business Settings (Owner only) ---
          if (canEditBusiness && settings != null) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: 'Business Settings'),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Store Name'),
                    subtitle: Text(
                        settings.storeName.isNotEmpty ? settings.storeName : 'Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreName(context, settings),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Store Address'),
                    subtitle: Text(
                        settings.storeAddress.isNotEmpty ? settings.storeAddress : 'Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      settings,
                      'Store Address',
                      'store_address',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Store Contact'),
                    subtitle: Text(
                        settings.storePhone.isNotEmpty ? settings.storePhone : 'Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      settings,
                      'Store Contact',
                      'store_phone',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Receipt Footer'),
                    subtitle: Text(
                        (settings.receiptFooter != null && settings.receiptFooter!.isNotEmpty)
                            ? settings.receiptFooter!
                            : 'Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editStoreField(
                      context,
                      settings,
                      'Receipt Footer',
                      'receipt_footer',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Currency'),
                    subtitle: Text(_currencyLabel(settings.currency)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showCurrencyDialog(context, settings),
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
                      title: const Text('Backup & Restore'),
                      subtitle: const Text('Create, restore, and manage database backups'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _navigateToBackupRestore(context),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _currencyLabel(String currency) {
    return switch (currency) {
      'PHP' => 'Philippine Peso (₱)',
      'USD' => 'US Dollar (\$)',
      'EUR' => 'Euro (€)',
      _ => currency,
    };
  }

  Future<void> _navigateToBackupRestore(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
    );
  }

  Future<void> _editStoreName(BuildContext context, Settings settings) async {
    final settingsService = ref.read(settingsServiceProvider);
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
      try {
        await settingsService.updateSettings(settings.copyWith(storeName: result));
        await _loadSettings();
        if (context.mounted) {
          await AppDialogService.success(context, title: 'Updated', message: 'Store name updated.');
        }
      } catch (e) {
        if (context.mounted) {
          AppDialogService.error(context, title: 'Error', message: 'Failed to update store name.');
        }
      }
    }
  }

  Future<void> _editStoreField(
    BuildContext context,
    Settings settings,
    String label,
    String fieldKey,
  ) async {
    final settingsService = ref.read(settingsServiceProvider);

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
      try {
        await settingsService.updateSettings(updated);
        await _loadSettings();
        if (context.mounted) {
          await AppDialogService.success(context, title: 'Updated', message: '$label updated.');
        }
      } catch (e) {
        if (context.mounted) {
          AppDialogService.error(context, title: 'Error', message: 'Failed to update $label.');
        }
      }
    }
  }

  void _showCurrencyDialog(BuildContext context, Settings settings) {
    final currencies = ['PHP', 'USD', 'EUR'];
    final current = settings.currency;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: currencies
              .map((currency) => ListTile(
                    title: Text(_currencyLabel(currency)),
                    leading: Icon(
                      currency == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      final settingsService = ref.read(settingsServiceProvider);
                      try {
                        await settingsService.updateSettings(
                          settings.copyWith(currency: currency),
                        );
                        await _loadSettings();
                        if (context.mounted) {
                          await AppDialogService.success(context, title: 'Updated', message: 'Currency updated.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          AppDialogService.error(context, title: 'Error', message: 'Failed to update currency.');
                        }
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
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
    final colors = AppColors.userAccentColors.keys.toList();
    final authState = ref.read(authStateProvider);
    final user = authState.user;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accent Color'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: colors.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final color = colors[index];
              final isSelected = color == currentColor;
              return _ColorOption(
                name: color,
                color: AppColors.getUserAccentColor(color),
                isSelected: isSelected,
                onTap: () async {
                  if (user != null) {
                    final success = await ref
                        .read(authStateProvider.notifier)
                        .updateProfile(
                          userId: user.id!,
                          fullName: user.fullName,
                          colorPreference: color,
                        );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      if (success) {
                        await AppDialogService.success(dialogContext, title: 'Updated', message: 'Accent color updated.');
                      } else {
                        AppDialogService.error(dialogContext, title: 'Error', message: 'Failed to update accent color.');
                      }
                    }
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
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

class _ColorOption extends StatelessWidget {
  final String name;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.name,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${name[0].toUpperCase()}${name.substring(1)} accent',
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name[0].toUpperCase() + name.substring(1),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
