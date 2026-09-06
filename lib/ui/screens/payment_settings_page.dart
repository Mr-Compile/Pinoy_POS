import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// GCash / payment configuration page.
///
/// Requires `edit_settings` permission (Owner only for business settings).
/// Controls whether GCash is enabled, the reference / customer / proof
/// requirements, and the single authoritative verification policy:
/// whether Staff-tendered GCash sales need an authorized verifier's
/// approval, and who is allowed to verify. The Owner's own sales never
/// require verification.
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
    if (!SessionManager().canEditBusinessSettings()) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'You do not have permission to access Payment Settings.';
        });
      }
      return;
    }

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

  Future<void> _uploadGcashQr() async {
    setState(() => _isLoading = true);
    try {
      final settingsService = ref.read(settingsServiceProvider);
      final result = await settingsService.updateGcashQrImage();
      if (!mounted) return;

      if (result.isSuccess) {
        ref.invalidate(paymentSettingsProvider);
        await AppDialogService.success(
          context,
          title: 'QR Image Saved',
          message: 'The GCash QR image has been uploaded.',
        );
        await _loadSettings();
      } else {
        setState(() => _isLoading = false);
        AppDialogService.error(
          context,
          title: 'Upload Failed',
          message: result.error ?? 'Could not upload the GCash QR image.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppDialogService.error(
          context,
          title: 'Upload Failed',
          message: 'Could not upload the GCash QR image.',
        );
      }
    }
  }

  Future<void> _clearGcashQr() async {
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: 'GCash QR image',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final settingsService = ref.read(settingsServiceProvider);
      await settingsService.clearGcashQrImage();
      ref.invalidate(paymentSettingsProvider);
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to remove the GCash QR image.',
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
                      onUploadGcashQr: _uploadGcashQr,
                      onClearGcashQr: _clearGcashQr,
                      isLoading: _isLoading,
                    ),
    );
  }
}

class _PaymentSettingsForm extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onSave;
  final VoidCallback onUploadGcashQr;
  final VoidCallback onClearGcashQr;
  final bool isLoading;

  const _PaymentSettingsForm({
    required this.settings,
    required this.onSave,
    required this.onUploadGcashQr,
    required this.onClearGcashQr,
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
  late bool _verificationRequired;
  late String _verifierScope;
  late int _referenceMinLength;

  @override
  void initState() {
    super.initState();
    _gcashEnabled = widget.settings.gcashEnabled;
    _gcashReferenceRequired = widget.settings.gcashReferenceRequired;
    _customerNameRequirement = widget.settings.gcashCustomerNameRequirement;
    _paymentProofRequirement = widget.settings.gcashPaymentProofRequirement;
    // The stored mode distinguishes "who can verify" ('owner' vs
    // 'owner_admin'); 'immediate' means verification is off. The legacy
    // 'admin' value is folded into 'owner_admin' because the Owner must
    // always remain an authorized verifier.
    _verificationRequired =
        widget.settings.gcashVerificationMode != 'immediate';
    _verifierScope =
        widget.settings.gcashVerificationMode == 'owner_admin' ||
                widget.settings.gcashVerificationMode == 'admin'
            ? 'owner_admin'
            : 'owner';
    _referenceMinLength = widget.settings.gcashReferenceMinLength;
  }

  static const _customerNameOptions = ['off', 'optional', 'required'];
  static const _proofOptions = ['off', 'optional', 'required'];
  static const _verifierOptions = ['owner', 'owner_admin'];

  String _label(String key) {
    return switch (key) {
      'off' => 'Off',
      'optional' => 'Optional',
      'required' => 'Required',
      'owner' => 'Owner only',
      'owner_admin' => 'Owner or System Admin',
      _ => key,
    };
  }

  String get _verificationInfoText {
    if (!_verificationRequired) {
      return 'GCash sales are confirmed immediately for every operator.';
    }
    final verifier =
        _verifierScope == 'owner_admin' ? 'an Owner or System Admin' : 'the Owner';
    return 'GCash sales tendered by Staff must be approved by $verifier '
        'before the sale is completed. Sales tendered by the Owner are '
        'always confirmed immediately and never require verification.';
  }

  Widget _buildGcashQrSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage =
        widget.settings.gcashQrImagePath != null &&
        widget.settings.gcashQrImagePath!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Merchant QR Code',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: AspectRatio(
              aspectRatio: 1,
              child: hasImage
                  ? AppImage(
                      imagePath: widget.settings.gcashQrImagePath,
                      placeholderIcon: Icons.qr_code,
                      fit: BoxFit.contain,
                      cacheWidth: null,
                      semanticLabel: 'GCash merchant QR code',
                    )
                  : _buildQrPlaceholder(cs),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LoadingButton(
                  isLoading: widget.isLoading,
                  onPressed: widget.isLoading
                      ? null
                      : () => widget.onUploadGcashQr(),
                  label: hasImage ? 'Change QR Image' : 'Upload QR Image',
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: LoadingButton(
                    isLoading: widget.isLoading,
                    onPressed: widget.isLoading
                        ? null
                        : () => widget.onClearGcashQr(),
                    label: 'Remove',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrPlaceholder(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code, size: 48, color: cs.outline),
            const SizedBox(height: 8),
            Text(
              'No GCash QR image uploaded',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final updated = widget.settings.copyWith(
      gcashEnabled: _gcashEnabled,
      gcashReferenceRequired: _gcashReferenceRequired,
      gcashCustomerNameRequirement: _customerNameRequirement,
      gcashPaymentProofRequirement: _paymentProofRequirement,
      gcashVerificationMode:
          _verificationRequired ? _verifierScope : 'immediate',
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
                SwitchListTile(
                  title: const Text('Verify staff GCash sales'),
                  subtitle: const Text(
                      'Staff GCash payments must be approved by an authorized verifier before the sale is completed.'),
                  value: _verificationRequired,
                  onChanged: widget.isLoading
                      ? null
                      : (value) =>
                          setState(() => _verificationRequired = value),
                ),
                if (_verificationRequired)
                  ListTile(
                    title: const Text('Who can verify'),
                    subtitle: Text(_label(_verifierScope)),
                    trailing: DropdownButton<String>(
                      value: _verifierScope,
                      onChanged: widget.isLoading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _verifierScope = value);
                            },
                      items: _verifierOptions
                          .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(_label(v)),
                              ))
                          .toList(),
                    ),
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Minimum reference length'),
                  subtitle: Text('$_referenceMinLength characters'),
                  trailing: SizedBox(
                    width: 80,
                    child: AppTextFormField(
                      initialValue: _referenceMinLength.toString(),
                      keyboardType: TextInputType.number,
                      enabled: !widget.isLoading,
                      onChanged: (value) {
                        final parsed = int.tryParse(value) ?? 1;
                        setState(() => _referenceMinLength = parsed.clamp(1, 50));
                      },
                      isDense: true,
                    ),
                  ),
                ),
                const Divider(),
                _buildGcashQrSection(context),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                      _verificationInfoText,
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
