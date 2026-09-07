import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_preview.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_viewer.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// GCash / payment configuration page.
///
/// Requires business-Owner privileges (see [SessionManager.canEditBusinessSettings]).
/// The page is Riverpod-driven: it watches [settingsProvider], refreshes
/// automatically on save, and keeps the previous UI visible while a save or
/// QR upload is in flight.
class PaymentSettingsPage extends ConsumerWidget {
  const PaymentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!SessionManager().canEditBusinessSettings()) {
      return const Scaffold(
        appBar: AppHeader(
          title: 'Payment Settings',
          showBackButton: true,
        ),
        body: ErrorState(
          title: 'Access Denied',
          message: 'You do not have permission to access Payment Settings.',
        ),
      );
    }

    final settingsValue = ref.watch(settingsProvider);

    return Scaffold(
      appBar: const AppHeader(
        title: 'Payment Settings',
        showBackButton: true,
      ),
      body: settingsValue.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(
          title: 'Failed to Load',
          message: 'Failed to load payment settings.',
          onRetry: () => ref.invalidate(settingsProvider),
        ),
        data: (settings) => _PaymentSettingsForm(
          settings: settings,
          isLoading: settingsValue.isLoading,
          onSave: (updated) => _save(context, ref, updated),
          onUploadGcashQr: () => _uploadGcashQr(context, ref),
          onClearGcashQr: () => _clearGcashQr(context, ref),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, Settings updated) async {
    try {
      await ref.read(settingsServiceProvider).updateSettings(updated);
      ref.invalidate(settingsProvider);
      await ref.read(settingsProvider.future);
      if (context.mounted) {
        await AppDialogService.success(
          context,
          title: 'Saved',
          message: 'Payment settings updated successfully.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to save payment settings.',
        );
      }
    }
  }

  Future<void> _uploadGcashQr(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(settingsServiceProvider).updateGcashQrImage();
      if (!context.mounted) return;

      if (result.isSuccess) {
        ref.invalidate(settingsProvider);
        await ref.read(settingsProvider.future);
        if (context.mounted) {
          await AppDialogService.success(
            context,
            title: 'QR Image Saved',
            message: 'The GCash QR image has been uploaded.',
          );
        }
      } else {
        AppDialogService.error(
          context,
          title: 'Upload Failed',
          message: result.error ?? 'Could not upload the GCash QR image.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogService.error(
          context,
          title: 'Upload Failed',
          message: 'Could not upload the GCash QR image.',
        );
      }
    }
  }

  Future<void> _clearGcashQr(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: 'GCash QR image',
    );
    if (confirmed != true) return;

    try {
      await ref.read(settingsServiceProvider).clearGcashQrImage();
      ref.invalidate(settingsProvider);
      await ref.read(settingsProvider.future);
      if (context.mounted) {
        await AppDialogService.success(
          context,
          title: 'Removed',
          message: 'The GCash QR image has been removed.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to remove the GCash QR image.',
        );
      }
    }
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
  late int _referenceMinLength;

  static const _customerNameOptions = ['off', 'optional', 'required'];
  static const _proofOptions = ['off', 'optional', 'required'];

  @override
  void initState() {
    super.initState();
    _syncFromSettings();
  }

  @override
  void didUpdateWidget(covariant _PaymentSettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings != oldWidget.settings) {
      _syncFromSettings();
    }
  }

  void _syncFromSettings() {
    _gcashEnabled = widget.settings.gcashEnabled;
    _gcashReferenceRequired = widget.settings.gcashReferenceRequired;
    _customerNameRequirement = widget.settings.gcashCustomerNameRequirement;
    _paymentProofRequirement = widget.settings.gcashPaymentProofRequirement;
    _verificationRequired = widget.settings.gcashVerificationMode != 'immediate';
    _referenceMinLength = widget.settings.gcashReferenceMinLength;
  }

  String _label(String key) {
    return switch (key) {
      'off' => 'Off',
      'optional' => 'Optional',
      'required' => 'Required',
      _ => key,
    };
  }

  String get _verificationInfoText {
    if (!_verificationRequired) {
      return 'GCash sales are confirmed immediately for every operator.';
    }
    return 'GCash sales tendered by Staff must be approved by the Owner '
        'before the sale is completed. Sales tendered by the Owner are '
        'always confirmed immediately and never require verification.';
  }

  void _openQrViewer(BuildContext context, String qrPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppPaymentQrViewer(
          imagePath: qrPath,
          title: 'Merchant QR Code',
          caption: 'Scan this QR code to pay',
        ),
      ),
    );
  }

  Widget _buildGcashQrSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qrPath = widget.settings.gcashQrImagePath;
    final hasImage = qrPath != null && qrPath.isNotEmpty;
    final safeQrPath = hasImage ? qrPath : null;

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
          AppPaymentQrPreview(
            imagePath: qrPath,
            onTap: safeQrPath != null ? () => _openQrViewer(context, safeQrPath) : null,
            emptyTitle: 'No GCash QR image uploaded',
            emptySubtitle: 'Upload a QR image so customers can scan it.',
            maxHeight: 240,
            emptyColor: cs.surfaceContainerHighest,
            emptyForegroundColor: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LoadingButton(
                  isLoading: widget.isLoading,
                  onPressed: widget.isLoading ? null : widget.onUploadGcashQr,
                  label: hasImage ? 'Change QR Image' : 'Upload QR Image',
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: LoadingButton(
                    isLoading: widget.isLoading,
                    onPressed: widget.isLoading ? null : widget.onClearGcashQr,
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

  void _submit() {
    final updated = widget.settings.copyWith(
      gcashEnabled: _gcashEnabled,
      gcashReferenceRequired: _gcashReferenceRequired,
      gcashCustomerNameRequirement: _customerNameRequirement,
      gcashPaymentProofRequirement: _paymentProofRequirement,
      gcashVerificationMode: _verificationRequired ? 'owner' : 'immediate',
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
                      'Staff GCash payments must be approved by the Owner before the sale is completed.'),
                  value: _verificationRequired,
                  onChanged: widget.isLoading
                      ? null
                      : (value) =>
                          setState(() => _verificationRequired = value),
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
