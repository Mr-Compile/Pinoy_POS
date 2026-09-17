import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/phone_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
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
          message: 'Failed to load payment settings: $error',
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
    // Blocking, friendly progress dialog while the image is stored, the QR
    // is located for the auto-zoomed preview, and the payload is decoded.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _QrProcessingDialog(),
    ));

    void closeProcessing() {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final result = await ref.read(settingsServiceProvider).updateGcashQrImage();
      if (!context.mounted) return;

      if (!result.isSuccess) {
        closeProcessing();
        // Cancelling the image picker is not an error.
        if (result.error == 'No image selected') return;
        AppDialogService.error(
          context,
          title: 'Upload Failed',
          message: result.error ?? 'Could not upload the GCash QR image.',
        );
        return;
      }

      ref.invalidate(settingsProvider);
      ref.invalidate(paymentSettingsProvider);
      ref.invalidate(paymentQrDecodeProvider(result.filePath));

      // Decode before closing the dialog so the success message can report
      // the detected merchant and the "Detected from QR" card is populated
      // as soon as the page repaints.
      DecodedPaymentQr? decoded;
      try {
        decoded =
            await ref.read(paymentQrDecodeProvider(result.filePath).future);
      } catch (_) {
        decoded = null;
      }

      closeProcessing();
      await ref.read(settingsProvider.future);
      if (!context.mounted) return;

      final detectedMerchant = decoded?.merchantName;
      await AppDialogService.success(
        context,
        title: 'QR Image Saved',
        message: detectedMerchant != null
            ? 'Payment QR recognized for $detectedMerchant. The detected '
                'merchant details are shown on the payment screen.'
            : 'The GCash QR image has been uploaded and zoomed to the code.',
      );
    } catch (e) {
      closeProcessing();
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
  final _merchantNameController = TextEditingController();
  final _merchantPhoneController = TextEditingController();

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
    _merchantNameController.dispose();
    _merchantPhoneController.dispose();
    super.dispose();
  }

  void _syncFromSettings() {
    _merchantNameController.text = widget.settings.gcashMerchantName;
    _merchantPhoneController.text = widget.settings.gcashMerchantPhone;

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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Merchant Identity',
          style: AppTypography.titleMediumBold(context).copyWith(fontSize: 17),
        ),
        const SizedBox(height: 8),
        Text(
          'Fallback payee details for the GCash payment screen. When the '
          'uploaded QR already identifies the payee, the details detected '
          'from the QR are shown instead. Your Store Information name and '
          'contact number are managed separately.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        AppTextFormField(
          controller: _merchantNameController,
          label: 'Merchant Name',
          prefixIcon: Icons.storefront_outlined,
          hint: 'Payee name',
          helperText: 'Shown at checkout only when the QR does not '
              'identify the payee.',
          textCapitalization: TextCapitalization.words,
          enabled: !widget.isLoading,
        ),
        const SizedBox(height: 16),
        AppTextFormField(
          controller: _merchantPhoneController,
          label: 'GCash Mobile Number',
          prefixIcon: Icons.phone_outlined,
          hint: PhoneUtils.phMobileHint,
          helperText: 'The mobile number linked to the GCash account. '
              'Shown only when the QR carries no mobile number.',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhMobileInputFormatter()],
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
          if (hasImage) ...[
            const SizedBox(height: 12),
            _DetectedQrCard(qrPath: qrPath),
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
    final phone = _merchantPhoneController.text.trim();
    if (phone.isNotEmpty && !PhoneUtils.isValidPhMobile(phone)) {
      AppDialogService.error(
        context,
        title: 'Invalid Mobile Number',
        message: 'Enter an 11-digit PH mobile number '
            '(e.g. ${PhoneUtils.phMobileHint}).',
      );
      return;
    }

    final updated = widget.settings.copyWith(
      gcashMerchantName: _merchantNameController.text.trim(),
      gcashMerchantPhone: PhoneUtils.formatPhMobile(phone),
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
                      hint: '${AppConstants.minGcashReferenceLength}-50',
                      keyboardType: TextInputType.number,
                      enabled: !widget.isLoading,
                      onChanged: (value) {
                        final parsed = int.tryParse(value) ??
                            AppConstants.minGcashReferenceLength;
                        setState(() => _referenceMinLength = parsed.clamp(
                            AppConstants.minGcashReferenceLength, 50));
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


/// Blocking progress dialog shown while an uploaded GCash QR image is being
/// scanned, decoded, and cropped into the zoomed preview. It cycles through
/// friendly status lines so the owner knows the app is working.
class _QrProcessingDialog extends StatefulWidget {
  const _QrProcessingDialog();

  @override
  State<_QrProcessingDialog> createState() => _QrProcessingDialogState();
}

class _QrProcessingDialogState extends State<_QrProcessingDialog> {
  static const List<String> _steps = [
    'Locating the QR code in your image…',
    'Reading the merchant details…',
    'Zooming in on the QR code…',
  ];

  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted) return;
      setState(() => _step = (_step + 1) % _steps.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      type: AppDialogType.loading,
      title: 'Scanning QR Image',
      message: '${_steps[_step]}\nThis only takes a moment — please wait.',
      dismissible: false,
    );
  }
}

/// Shows the merchant details decoded from the uploaded payment QR inside
/// the Merchant QR Code section. Display-only: decoded values are shown on
/// the GCash payment screen but are never written into Merchant Identity.
class _DetectedQrCard extends ConsumerWidget {
  final String qrPath;

  const _DetectedQrCard({required this.qrPath});

  Widget _detailRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall(context).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final decodeAsync = ref.watch(paymentQrDecodeProvider(qrPath));

    if (decodeAsync.isLoading) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reading merchant details…',
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final decoded = decodeAsync.value;
    final fromQr =
        decoded?.detectionSource == PaymentQrDetectionSource.qrPayload;
    if (!fromQr || decoded == null || !decoded.hasMerchantInfo) {
      return _note(
        context,
        Icons.info_outline,
        'No merchant details were found in this QR. The image is still '
            'shown for manual scanning.',
      );
    }

    final showAccount =
        decoded.accountIdentifier != null && decoded.mobileNumber == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Payment QR recognized — shown at checkout, not saved',
                  style: AppTypography.labelSmall(context).copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (decoded.merchantName != null)
            _detailRow(context, 'Merchant', decoded.merchantName!),
          if (decoded.mobileNumber != null)
            _detailRow(context, 'Mobile', decoded.mobileNumber!),
          if (showAccount)
            _detailRow(context, 'Account', decoded.accountIdentifier!),
          if (decoded.paymentNetwork != null)
            _detailRow(context, 'Network', decoded.paymentNetwork!),
        ],
      ),
    );
  }
}
