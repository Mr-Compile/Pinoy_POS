import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// GCash / payment configuration page.
///
/// Requires `edit_settings` permission. Allows Owner and Admin to enable
/// GCash, require reference numbers / customer names / payment proof, and
/// choose whether pending payments need owner/admin verification.
class PaymentSettingsPage extends ConsumerStatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  ConsumerState<PaymentSettingsPage> createState() =>
      _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends ConsumerState<PaymentSettingsPage> {
  Settings? _settings;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
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
          _error = 'Failed to load payment settings.';
        });
      }
    }
  }

  Future<void> _save(Settings updated) async {
    setState(() => _isLoading = true);
    try {
      final settingsService = ref.read(settingsServiceProvider);
      await settingsService.updateSettings(updated);
      if (mounted) {
        setState(() => _isLoading = false);
        await AppDialogService.success(
          context,
          title: 'Saved',
          message: 'Payment settings updated successfully.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to save payment settings.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;

    return Scaffold(
      appBar: const AppHeader(
        title: 'Payment Settings',
        showBackButton: true,
      ),
      body: _isLoading && settings == null
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  title: 'Failed to Load',
                  message: _error!,
                  onRetry: _loadSettings,
                )
              : settings == null
                  ? const Center(child: Text('No settings found.'))
                  : _PaymentSettingsForm(
                      settings: settings,
                      onSave: _save,
                      isLoading: _isLoading,
                    ),
    );
  }
}

class _PaymentSettingsForm extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onSave;
  final bool isLoading;

  const _PaymentSettingsForm({
    required this.settings,
    required this.onSave,
    required this.isLoading,
  });

  @override
  State<_PaymentSettingsForm> createState() => _PaymentSettingsFormState();
}

class _PaymentSettingsFormState extends State<_PaymentSettingsForm> {
  late bool _gcashEnabled;
  late bool _gcashReferenceRequired;
  late String _customerNameRequirement;
  late String _paymentProofRequirement;
  late String _verificationMode;
  late int _referenceMinLength;

  @override
  void initState() {
    super.initState();
    _gcashEnabled = widget.settings.gcashEnabled;
    _gcashReferenceRequired = widget.settings.gcashReferenceRequired;
    _customerNameRequirement = widget.settings.gcashCustomerNameRequirement;
    _paymentProofRequirement = widget.settings.gcashPaymentProofRequirement;
    _verificationMode = widget.settings.gcashVerificationMode;
    _referenceMinLength = widget.settings.gcashReferenceMinLength;
  }

  static const _customerNameOptions = ['off', 'optional', 'required'];
  static const _proofOptions = ['off', 'optional', 'required'];
  static const _verificationOptions = ['immediate', 'owner', 'admin', 'owner_admin'];

  String _label(String key) {
    return switch (key) {
      'off' => 'Off',
      'optional' => 'Optional',
      'required' => 'Required',
      'immediate' => 'Immediate Confirmation',
      'owner' => 'Require Owner Verification',
      'admin' => 'Require Admin Verification',
      'owner_admin' => 'Require Owner or Admin Verification',
      _ => key,
    };
  }

  String _verificationInfoText(String mode) {
    return switch (mode) {
      'owner' => 'Only an Owner can confirm pending GCash sales.',
      'admin' => 'Only an Admin can confirm pending GCash sales.',
      'owner_admin' => 'An Owner or Admin can confirm pending GCash sales.',
      _ => 'GCash sales are confirmed automatically.',
    };
  }

  void _submit() {
    final updated = widget.settings.copyWith(
      gcashEnabled: _gcashEnabled,
      gcashReferenceRequired: _gcashReferenceRequired,
      gcashCustomerNameRequirement: _customerNameRequirement,
      gcashPaymentProofRequirement: _paymentProofRequirement,
      gcashVerificationMode: _verificationMode,
      gcashReferenceMinLength: _referenceMinLength,
    );
    widget.onSave(updated);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GCash',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enable GCash payments'),
                  value: _gcashEnabled,
                  onChanged: widget.isLoading
                      ? null
                      : (value) => setState(() => _gcashEnabled = value),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Reference number required'),
                  subtitle: const Text(
                      'Cashiers must enter the GCash reference number.'),
                  value: _gcashReferenceRequired,
                  onChanged: widget.isLoading
                      ? null
                      : (value) =>
                          setState(() => _gcashReferenceRequired = value),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Customer name'),
                  subtitle: Text(_label(_customerNameRequirement)),
                  trailing: DropdownButton<String>(
                    value: _customerNameRequirement,
                    onChanged: widget.isLoading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _customerNameRequirement = value);
                          },
                    items: _customerNameOptions
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(_label(v)),
                            ))
                        .toList(),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Payment proof'),
                  subtitle: Text(_label(_paymentProofRequirement)),
                  trailing: DropdownButton<String>(
                    value: _paymentProofRequirement,
                    onChanged: widget.isLoading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _paymentProofRequirement = value);
                          },
                    items: _proofOptions
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(_label(v)),
                            ))
                        .toList(),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verification',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outline),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _verificationMode,
                          underline: const SizedBox(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onChanged: widget.isLoading
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _verificationMode = value);
                                },
                          items: _verificationOptions
                              .map((v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(_label(v)),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose who must confirm pending GCash payments.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Minimum reference length'),
                  subtitle: Text('$_referenceMinLength characters'),
                  trailing: SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: _referenceMinLength.toString(),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      enabled: !widget.isLoading,
                      onChanged: (value) {
                        final parsed = int.tryParse(value) ?? 1;
                        setState(() => _referenceMinLength = parsed.clamp(1, 50));
                      },
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_verificationMode != 'immediate')
            AppCard(
              color: cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.onSecondaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _verificationInfoText(_verificationMode),
                        style: TextStyle(color: cs.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: LoadingButton(
              isLoading: widget.isLoading,
              onPressed: widget.isLoading ? null : _submit,
              label: 'Save Payment Settings',
            ),
          ),
        ],
      ),
    );
  }
}
