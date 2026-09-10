import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_preview.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_viewer.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
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
      ref.invalidate(paymentSettingsProvider);
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
        ref.invalidate(paymentSettingsProvider);
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
      ref.invalidate(paymentSettingsProvider);
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
  final _storeNameController = TextEditingController();
  final _storePhoneController = TextEditingController();

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

  @override
  void dispose() {
    _storeNameController.dispose();
    _storePhoneController.dispose();
    super.dispose();
  }

  void _syncFromSettings() {
    _storeNameController.text = widget.settings.storeName;
    _storePhoneController.text = widget.settings.storePhone;

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

  Widget _buildToggleRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSelectRow({
    required String title,
    required String value,
    required Widget child,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title),
      subtitle: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: child,
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> options,
    required ValueChanged<String?>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;

    return DropdownButton<String>(
      value: value,
      onChanged: onChanged,
      underline: const SizedBox.shrink(),
      isDense: true,
      icon: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
      dropdownColor: cs.surface,
      style: AppTypography.bodyMedium(context).copyWith(
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      items: options
          .map((v) => DropdownMenuItem(
                value: v,
                child: Text(_label(v)),
              ))
          .toList(),
    );
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

  Widget _buildMerchantIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Merchant Identity',
          style: AppTypography.titleMediumBold(context).copyWith(fontSize: 17),
        ),
        const SizedBox(height: 16),
        AppTextFormField(
          controller: _storeNameController,
          label: 'Store Name',
          prefixIcon: Icons.store_outlined,
          hint: 'Your store name',
          helperText: 'Shown to customers on the GCash payment screen.',
          textCapitalization: TextCapitalization.words,
          enabled: !widget.isLoading,
        ),
        const SizedBox(height: 16),
        AppTextFormField(
          controller: _storePhoneController,
          label: 'GCash Mobile Number',
          prefixIcon: Icons.phone_outlined,
          hint: '09XX XXX XXXX',
          helperText: 'The mobile number linked to the GCash account.',
          keyboardType: TextInputType.phone,
          enabled: !widget.isLoading,
        ),
      ],
    );
  }

  Widget _buildGcashQrSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qrPath = widget.settings.gcashQrImagePath;
    final previewPath = widget.settings.gcashQrPreviewPath;
    final displayQrPath = previewPath?.isNotEmpty == true ? previewPath : qrPath;
    final hasImage = qrPath != null && qrPath.isNotEmpty;
    final hasPreview = previewPath != null && previewPath.isNotEmpty;
    final safeQrPath = displayQrPath;

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
          LayoutBuilder(
            builder: (context, constraints) {
              final maxQrWidth =
                  constraints.maxWidth < 312 ? constraints.maxWidth - 32 : 280.0;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxQrWidth),
                  child: AppPaymentQrPreview(
                    imagePath: displayQrPath,
                    onTap: safeQrPath != null
                        ? () => _openQrViewer(context, safeQrPath)
                        : null,
                    emptyTitle: 'No GCash QR image uploaded',
                    emptySubtitle: 'Upload a QR image so customers can scan it.',
                    maxHeight: maxQrWidth,
                    emptyColor: cs.surfaceContainerHighest,
                    emptyForegroundColor: cs.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
          if (hasImage && !hasPreview) ...[
            const SizedBox(height: 8),
            Text(
              'QR code could not be detected automatically. The original image will be used.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = layoutClassFor(constraints.maxWidth).isCompact;
              final uploadButton = AppButton.filled(
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : widget.onUploadGcashQr,
                icon: Icons.upload,
                label: hasImage ? 'Change QR Image' : 'Upload QR Image',
                fullWidth: isCompact,
              );
              final removeButton = AppButton.destructive(
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : widget.onClearGcashQr,
                icon: Icons.delete_outline,
                label: 'Remove',
                fullWidth: isCompact,
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    uploadButton,
                    if (hasImage) ...[
                      const SizedBox(height: 12),
                      removeButton,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: uploadButton),
                  if (hasImage) ...[
                    const SizedBox(width: 12),
                    Expanded(child: removeButton),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _submit() {
    final updated = widget.settings.copyWith(
      storeName: _storeNameController.text.trim(),
      storePhone: _storePhoneController.text.trim(),
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
            child: _buildMerchantIdentitySection(),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'GCash',
                    style: AppTypography.titleMediumBold(context)
                        .copyWith(fontSize: 17),
                  ),
                ),
                const SizedBox(height: 8),
                _buildToggleRow(
                  title: 'Enable GCash payments',
                  value: _gcashEnabled,
                  onChanged: widget.isLoading
                      ? null
                      : (value) => setState(() => _gcashEnabled = value),
                ),
                _buildToggleRow(
                  title: 'Reference number required',
                  subtitle: 'Cashiers must enter the GCash reference number.',
                  value: _gcashReferenceRequired,
                  onChanged: widget.isLoading
                      ? null
                      : (value) =>
                          setState(() => _gcashReferenceRequired = value),
                ),
                _buildSelectRow(
                  title: 'Customer name',
                  value: _label(_customerNameRequirement),
                  child: _buildDropdown(
                    value: _customerNameRequirement,
                    options: _customerNameOptions,
                    onChanged: widget.isLoading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _customerNameRequirement = value);
                          },
                  ),
                ),
                _buildSelectRow(
                  title: 'Payment proof',
                  value: _label(_paymentProofRequirement),
                  child: _buildDropdown(
                    value: _paymentProofRequirement,
                    options: _proofOptions,
                    onChanged: widget.isLoading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _paymentProofRequirement = value);
                          },
                  ),
                ),
                _buildToggleRow(
                  title: 'Verify staff GCash sales',
                  subtitle:
                      'Staff GCash payments must be approved by the Owner before the sale is completed.',
                  value: _verificationRequired,
                  onChanged: widget.isLoading
                      ? null
                      : (value) =>
                          setState(() => _verificationRequired = value),
                ),
                _buildSelectRow(
                  title: 'Minimum reference length',
                  value: '$_referenceMinLength characters',
                  child: SizedBox(
                    width: 80,
                    child: AppTextFormField(
                      initialValue: _referenceMinLength.toString(),
                      hint: '1-50',
                      keyboardType: TextInputType.number,
                      enabled: !widget.isLoading,
                      onChanged: (value) {
                        final parsed = int.tryParse(value) ?? 1;
                        setState(
                            () => _referenceMinLength = parsed.clamp(1, 50));
                      },
                      isDense: true,
                    ),
                  ),
                ),
                _buildGcashQrSection(context),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _verificationInfoText,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          AppButton.filled(
            isLoading: widget.isLoading,
            onPressed: widget.isLoading ? null : _submit,
            icon: Icons.save,
            label: 'Save Payment Settings',
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}
