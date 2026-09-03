import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
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
          title: 'Store Information',
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: const AppHeader(
          title: 'Store Information',
          showBackButton: true,
        ),
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
          title: 'Store Information',
          showBackButton: true,
        ),
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
                  subtitle: Text(
                    settings.storeName.isNotEmpty
                        ? settings.storeName
                        : 'Not set',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editStoreName(settings),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Store Address'),
                  subtitle: Text(
                    settings.storeAddress.isNotEmpty
                        ? settings.storeAddress
                        : 'Not set',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editStoreField(
                    settings,
                    'Store Address',
                    'store_address',
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Store Contact'),
                  subtitle: Text(
                    settings.storePhone.isNotEmpty
                        ? settings.storePhone
                        : 'Not set',
                  ),
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
                        : 'Not set',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editStoreField(
                    settings,
                    'Receipt Footer',
                    'receipt_footer',
                  ),
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
      'PHP' => 'Philippine Peso (${CurrencyUtils.symbol(currency: 'PHP')})',
      'USD' => 'US Dollar (\$)',
      'EUR' => 'Euro (€)',
      _ => currency,
    };
  }

  Future<ModalResult<String>?> _showTextEditDialog({
    required String title,
    required String label,
    required String initialValue,
    int maxLines = 1,
  }) {
    return showDialog<ModalResult<String>>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AppDialogForm<ModalResult<String>>(
        type: AppDialogType.info,
        title: title,
        childBuilder: (context, state) {
          final controller = state.textController('value', text: initialValue);

          return TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            maxLines: maxLines,
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                state.pop(const ModalResult<String>.cancelled()),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            onPressed: (context) => state.pop(
              ModalResult<String>.saved(
                state.textController('value').text.trim(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editStoreName(Settings settings) async {
    final settingsService = ref.read(settingsServiceProvider);
    final result = await _showTextEditDialog(
      title: 'Store Name',
      label: 'Store Name',
      initialValue: settings.storeName,
    );

    if (result?.isSaved == true && result!.value!.isNotEmpty && mounted) {
      try {
        await settingsService.updateSettings(
          settings.copyWith(storeName: result.value!),
        );
        await _loadSettings();
        if (mounted) {
          await AppDialogService.success(
            context,
            title: 'Updated',
            message: 'Store name updated.',
          );
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Failed to update store name.',
          );
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

    final result = await _showTextEditDialog(
      title: label,
      label: label,
      initialValue: currentValue,
      maxLines: fieldKey == 'receipt_footer' ? 2 : 1,
    );

    if (result?.isSaved == true && mounted) {
      final updated = settings.copyWith(
        storeAddress: fieldKey == 'store_address' ? result!.value! : null,
        storePhone: fieldKey == 'store_phone' ? result!.value! : null,
        receiptFooter: fieldKey == 'receipt_footer' ? result!.value! : null,
      );
      try {
        await settingsService.updateSettings(updated);
        await _loadSettings();
        if (mounted) {
          await AppDialogService.success(
            context,
            title: 'Updated',
            message: '$label updated.',
          );
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Failed to update $label.',
          );
        }
      }
    }
  }

  Future<String?> _showCurrencyDialog(Settings settings) async {
    final currencies = ['PHP', 'USD', 'EUR'];
    final current = settings.currency;

    final result = await showDialog<String>(
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
              .map(
                (currency) => ListTile(
                  title: Text(_currencyLabel(currency)),
                  leading: Icon(
                    currency == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => Navigator.of(
                    dialogContext,
                    rootNavigator: true,
                  ).pop(currency),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (result != null && mounted) {
      final settingsService = ref.read(settingsServiceProvider);
      try {
        await settingsService.updateSettings(
          settings.copyWith(currency: result),
        );
        await _loadSettings();
        if (mounted) {
          await AppDialogService.success(
            context,
            title: 'Updated',
            message: 'Currency updated.',
          );
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Failed to update currency.',
          );
        }
      }
    }

    return result;
  }
}
