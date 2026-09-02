import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Store Information settings sub-page — business settings (Owner only).
///
/// Requires `edit_settings` permission. Shows store name, address,
/// contact, receipt footer, and currency — all editable via dialogs.
class StoreInformationSettingsPage extends ConsumerStatefulWidget {
  const StoreInformationSettingsPage({super.key});

  @override
  ConsumerState<StoreInformationSettingsPage> createState() =>
      _StoreInformationSettingsPageState();
}

class _StoreInformationSettingsPageState
    extends ConsumerState<StoreInformationSettingsPage> {
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
      if (mounted) {
        setState(() {
          _settings = settings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load store information.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: const AppHeader(
            title: 'Store Information', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: const AppHeader(
            title: 'Store Information', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load',
          message: _loadError!,
          onRetry: _loadSettings,
        ),
      );
    }

    final settings = _settings;
    if (settings == null) {
      return Scaffold(
        appBar: const AppHeader(
            title: 'Store Information', showBackButton: true),
        body: const Center(child: Text('No settings found.')),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Store Information', showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text('Store Name'),
                  subtitle: Text(settings.storeName.isNotEmpty
                      ? settings.storeName
                      : 'Not set'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editStoreName(settings),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Store Address'),
                  subtitle: Text(settings.storeAddress.isNotEmpty
                      ? settings.storeAddress
                      : 'Not set'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _editStoreField(settings, 'Store Address', 'store_address'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Store Contact'),
                  subtitle: Text(settings.storePhone.isNotEmpty
                      ? settings.storePhone
                      : 'Not set'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _editStoreField(settings, 'Store Contact', 'store_phone'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Receipt Footer'),
                  subtitle: Text(
                      (settings.receiptFooter != null &&
                              settings.receiptFooter!.isNotEmpty)
                          ? settings.receiptFooter!
                          : 'Not set'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editStoreField(
                      settings, 'Receipt Footer', 'receipt_footer'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Currency'),
                  subtitle: Text(_currencyLabel(settings.currency)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showCurrencyDialog(settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _currencyLabel(String currency) {
    return switch (currency) {
      'PHP' => 'Philippine Peso (₱)',
      'USD' => 'US Dollar (\$)',
      'EUR' => 'Euro (€)',
      _ => currency,
    };
  }

  Future<void> _editStoreName(Settings settings) async {
    final settingsService = ref.read(settingsServiceProvider);
    final controller = TextEditingController(text: settings.storeName);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AppDialog(
        type: AppDialogType.info,
        title: 'Store Name',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            onPressed: (context) => Navigator.of(context, rootNavigator: true)
                .pop(controller.text.trim()),
          ),
        ],
        child: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Store Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      try {
        await settingsService
            .updateSettings(settings.copyWith(storeName: result));
        await _loadSettings();
        if (mounted) {
          await AppDialogService.success(context,
              title: 'Updated', message: 'Store name updated.');
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context,
              title: 'Error', message: 'Failed to update store name.');
        }
      }
    }
  }

  Future<void> _editStoreField(
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
      useRootNavigator: true,
      builder: (context) => AppDialog(
        type: AppDialogType.info,
        title: label,
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            onPressed: (context) => Navigator.of(context, rootNavigator: true)
                .pop(controller.text.trim()),
          ),
        ],
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: fieldKey == 'receipt_footer' ? 2 : 1,
        ),
      ),
    );

    if (result != null && mounted) {
      final updated = settings.copyWith(
        storeAddress: fieldKey == 'store_address' ? result : null,
        storePhone: fieldKey == 'store_phone' ? result : null,
        receiptFooter: fieldKey == 'receipt_footer' ? result : null,
      );
      try {
        await settingsService.updateSettings(updated);
        await _loadSettings();
        if (mounted) {
          await AppDialogService.success(context,
              title: 'Updated', message: '$label updated.');
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context,
              title: 'Error', message: 'Failed to update $label.');
        }
      }
    }
  }

  void _showCurrencyDialog(Settings settings) {
    final currencies = ['PHP', 'USD', 'EUR'];
    final current = settings.currency;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialog(
        type: AppDialogType.info,
        title: 'Currency',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
        child: Column(
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
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                      final settingsService =
                          ref.read(settingsServiceProvider);
                      try {
                        await settingsService.updateSettings(
                          settings.copyWith(currency: currency),
                        );
                        await _loadSettings();
                        if (mounted) {
                          await AppDialogService.success(context,
                              title: 'Updated',
                              message: 'Currency updated.');
                        }
                      } catch (e) {
                        if (mounted) {
                          AppDialogService.error(context,
                              title: 'Error',
                              message: 'Failed to update currency.');
                        }
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}
