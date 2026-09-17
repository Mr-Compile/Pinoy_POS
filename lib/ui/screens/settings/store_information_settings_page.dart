import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/phone_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Store Information settings sub-page — business settings (Owner only).
///
/// Requires business-Owner privileges (see
/// [SessionManager.canEditBusinessSettings]). Shows store name, address,
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

  /// Receipt surfaces read store identity through [settingsProvider],
  /// which is non-autoDispose, so saving here must invalidate it or those
  /// surfaces keep showing stale values. Payment Settings deliberately
  /// does not need invalidating — its GCash merchant identity is stored
  /// in separate `gcash_merchant_*` fields that this page never edits.
  void _invalidateSettingsProviders() {
    ref.invalidate(settingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!SessionManager().canEditBusinessSettings()) {
      return const Scaffold(
        appBar: AppHeader(
          title: 'Store Information',
          showBackButton: true,
        ),
        body: ErrorState(
          title: 'Access Denied',
          message:
              'You do not have permission to access Store Information.',
        ),
      );
    }

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
    String? hint,
    String? helperText,
    required String initialValue,
    int maxLines = 1,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return showDialog<ModalResult<String>>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AppDialogForm<ModalResult<String>>(
        type: AppDialogType.edit,
        title: title,
        childBuilder: (context, state) {
          final controller = state.textController('value', text: initialValue);

          return Form(
            key: state.formKey,
            child: AppTextFormField(
              controller: controller,
              label: label,
              hint: hint,
              helperText: helperText,
              prefixIcon: prefixIcon,
              maxLines: maxLines,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              validator: validator,
            ),
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
            onPressed: (context) {
              if (validator != null &&
                  !(state.formKey.currentState?.validate() ?? false)) {
                return;
              }
              state.pop(
                ModalResult<String>.saved(
                  state.textController('value').text.trim(),
                ),
              );
            },
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
      hint: 'Your store name',
      initialValue: settings.storeName,
      prefixIcon: Icons.storefront_outlined,
    );

    if (result?.isSaved == true && result!.value!.isNotEmpty && mounted) {
      try {
        await settingsService.updateSettings(
          settings.copyWith(storeName: result.value!),
        );
        _invalidateSettingsProviders();
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

    final prefixIcon = switch (fieldKey) {
      'store_address' => Icons.location_on_outlined,
      'store_phone' => Icons.phone_outlined,
      'receipt_footer' => Icons.receipt_long_outlined,
      _ => null,
    };

    final isPhone = fieldKey == 'store_phone';

    final hint = switch (fieldKey) {
      'store_address' => 'Store address',
      'store_phone' => PhoneUtils.phMobileHint,
      'receipt_footer' => AppConstants.defaultReceiptFooter,
      _ => null,
    };

    final result = await _showTextEditDialog(
      title: label,
      label: label,
      hint: hint,
      helperText: isPhone ? '11-digit PH mobile number.' : null,
      initialValue: currentValue,
      maxLines: fieldKey == 'receipt_footer' ? 2 : 1,
      prefixIcon: prefixIcon,
      keyboardType: isPhone ? TextInputType.phone : null,
      inputFormatters: isPhone ? [PhMobileInputFormatter()] : null,
      validator: isPhone
          ? (value) =>
              value == null ||
                      value.trim().isEmpty ||
                      PhoneUtils.isValidPhMobile(value)
                  ? null
                  : 'Enter an 11-digit PH mobile number '
                      '(e.g. ${PhoneUtils.phMobileHint}).'
          : null,
    );

    if (result?.isSaved == true && mounted) {
      final value = isPhone
          ? PhoneUtils.formatPhMobile(result!.value!)
          : result!.value!;
      final updated = settings.copyWith(
        storeAddress: fieldKey == 'store_address' ? value : null,
        storePhone: isPhone ? value : null,
        receiptFooter: fieldKey == 'receipt_footer' ? value : null,
      );
      try {
        await settingsService.updateSettings(updated);
        _invalidateSettingsProviders();
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
        showIcon: false,
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
        _invalidateSettingsProviders();
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
