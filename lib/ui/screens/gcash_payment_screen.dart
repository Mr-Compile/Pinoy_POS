import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/screens/payment_settings_page.dart';
import 'package:pinoy_pos/ui/screens/payment_success_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_preview.dart';
import 'package:pinoy_pos/ui/widgets/app_payment_qr_viewer.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// GCash payment flow: customer, reference, payment proof, review, confirm.
///
/// The GCash QR shown here is the merchant's uploaded static QR. It is *not*
/// regenerated with customer or amount data; the transaction amount and customer
/// name are stored with the sale and displayed to the operator separately.
class GcashPaymentScreen extends ConsumerStatefulWidget {
  final double total;

  const GcashPaymentScreen({super.key, required this.total});

  @override
  ConsumerState<GcashPaymentScreen> createState() => _GcashPaymentScreenState();
}

class _GcashPaymentScreenState extends ConsumerState<GcashPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController(text: 'GUEST');
  final _referenceController = TextEditingController();

  final ImageService _imageService = ImageService();

  String? _paymentProofPath;
  String? _paymentProofType;
  bool _isReviewing = false;
  bool _isProcessing = false;
  bool _committed = false;

  @override
  void dispose() {
    if (!_committed && _paymentProofPath != null) {
      _imageService.deleteImage(_paymentProofPath);
    }
    _customerController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String? _validateReference(PaymentSettings settings, String? value) {
    if (!settings.gcashReferenceRequired) return null;
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Reference number is required';
    }
    if (trimmed.length < settings.gcashReferenceMinLength) {
      return 'Reference number must be at least ${settings.gcashReferenceMinLength} characters';
    }
    return null;
  }

  String _customerNameLabel(PaymentSettings settings) {
    if (!settings.customerNameVisible) return 'Customer Name';
    if (settings.customerNameRequired) return 'Customer Name *';
    return 'Customer Name (optional)';
  }

  String? _validateCustomer(PaymentSettings settings, String? value) {
    if (!settings.customerNameRequired) return null;
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Customer name is required';
    }
    return null;
  }

  Future<void> _pickImage(ImageSource source) async {
    final result = await _imageService.pickAndStoreImage(
      source: source,
      directory: 'payment_evidence/tmp',
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _paymentProofPath = result.filePath;
        _paymentProofType = result.mediaType;
      });
    } else if (result.error != null) {
      AppDialogService.error(
        context,
        title: 'Unable to attach proof',
        message: result.error!,
      );
    }
  }

  void _removeProof() {
    if (_paymentProofPath != null) {
      _imageService.deleteImage(_paymentProofPath);
      setState(() {
        _paymentProofPath = null;
        _paymentProofType = null;
      });
    }
  }

  void _goToReview(PaymentSettings settings) {
    if (!_formKey.currentState!.validate()) return;

    if (settings.paymentProofRequired &&
        (_paymentProofPath == null || _paymentProofPath!.isEmpty)) {
      AppDialogService.error(
        context,
        title: 'Missing Payment Proof',
        message: 'A photo of the GCash payment is required.',
      );
      return;
    }

    setState(() => _isReviewing = true);
  }

  void _goBackToDetails() {
    setState(() => _isReviewing = false);
  }

  Future<void> _completeSale(PaymentSettings settings) async {
    // Re-entrancy guard: without this, a fast double-tap could open two
    // verification dialogs or start two concurrent createSale calls before
    // the loading state disables the button.
    if (_isProcessing) return;

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      AppDialogService.error(
        context,
        title: 'Empty Cart',
        message: 'The cart is empty. Add products before checkout.',
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final items = ref.read(cartProvider.notifier).toSaleItems();
      final success = await ref
          .read(salesServiceProvider)
          .createSale(
            items: items,
            totalAmount: widget.total,
            cashReceived: widget.total,
            paymentMethod: 'GCash',
            referenceNumber: _referenceController.text.trim(),
            customerName: _customerController.text.trim(),
            paymentProofPath: _paymentProofPath,
            paymentProofType: _paymentProofType,
            notes: null,
          );

      if (!mounted) return;

      if (success) {
        _committed = true;
        ref.read(cartProvider.notifier).clear();
        ref.read(cartProvider.notifier).setProcessing(false);
        // The sale decremented stock — refresh every catalog screen.
        bumpCatalogRevision(ref);

        // Load the created sale to pass to the success screen.
        // The most recent sale by the current user is the one just created.
        final sales = await ref.read(salesServiceProvider).getSales();
        final sale = sales.isNotEmpty ? sales.first : null;

        if (!mounted) return;

        if (sale != null) {
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => PaymentSuccessScreen(sale: sale)),
            (route) => route.isFirst,
          );
        } else {
          await AppDialogService.success(
            context,
            title: 'Sale Completed',
            message: 'GCash transaction saved successfully.',
          );
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        setState(() => _isProcessing = false);
        AppDialogService.error(
          context,
          title: 'Transaction Failed',
          message: 'Failed to complete the sale. Please try again.',
        );
      }
    } on PaymentValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isReviewing = false;
        });
        AppDialogService.error(
          context,
          title: 'Invalid GCash Payment',
          message: e.message,
          details: e.details,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isReviewing = false;
        });
        AppDialogService.error(
          context,
          title: 'Transaction Failed',
          message: 'An error occurred while processing the GCash payment.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(paymentSettingsProvider);

    return settingsAsync.when(
      loading: () => const Scaffold(
        appBar: AppHeader(title: 'GCash Payment', showBackButton: true),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: const AppHeader(title: 'GCash Payment', showBackButton: true),
        body: ErrorState(
          title: 'Unable to Load GCash Settings',
          message: err.toString(),
          onRetry: () => ref.invalidate(paymentSettingsProvider),
        ),
      ),
      data: (settings) => _buildPaymentScreen(settings, cs),
    );
  }

  Widget _buildPaymentScreen(PaymentSettings settings, ColorScheme cs) {
    if (!settings.gcashEnabled) {
      return Scaffold(
        appBar: const AppHeader(title: 'GCash Payment', showBackButton: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'GCash payments are currently disabled.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppHeader(
        title: _isReviewing ? 'Review Payment' : 'GCash Payment',
        subtitle: _isReviewing ? null : 'Scan QR to pay',
        showBackButton: true,
        onBackPressed: _isReviewing
            ? (_isProcessing ? null : _goBackToDetails)
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: _isReviewing
              ? _buildReview(settings, cs)
              : _buildDetails(settings, cs),
        ),
      ),
    );
  }

  Widget _buildDetails(PaymentSettings settings, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = layoutClassFor(constraints.maxWidth).isCompact;

        return Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.disabled,
          child: isCompact
              ? _buildCompactDetailsBody(settings, cs)
              : _buildWideDetailsBody(settings, cs),
        );
      },
    );
  }

  /// Portrait phone layout: one vertical column following the payment
  /// hierarchy exactly.
  ///
  /// Header → Amount → Scan to Pay / QR → Instructions → QR/merchant details
  /// → Customer / Reference → Proof (if enabled) → Order Summary
  /// → Review Payment.
  Widget _buildCompactDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTotalCard(cs),
        const SizedBox(height: Spacing.lg),
        _buildQrCard(settings, cs),
        _buildConfigureQrButton(settings, cs),
        _buildQrDetailsCard(settings, cs),
        const SizedBox(height: Spacing.xl),
        _buildCustomerInfoSection(settings, cs),
        const SizedBox(height: Spacing.xl),
        _buildOrderSummary(cs, maxVisibleItems: 2, compact: true),
        const SizedBox(height: Spacing.xl),
        AppButton.filled(
          fullWidth: true,
          icon: Icons.receipt_long_outlined,
          label: 'Review Payment',
          size: AppButtonSize.large,
          onPressed: () => _goToReview(settings),
        ),
        const SizedBox(height: Spacing.lg),
        _buildSecureNote(cs),
      ],
    );
  }

  /// Tablet / desktop layout: the QR dominates the left column while the
  /// right column carries amount, decoded payment details, required inputs,
  /// order summary and the primary action.
  Widget _buildWideDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildQrCard(settings, cs),
              _buildConfigureQrButton(settings, cs),
            ],
          ),
        ),
        const SizedBox(width: Spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTotalCard(cs),
              _buildQrDetailsCard(settings, cs),
              const SizedBox(height: Spacing.xl),
              _buildCustomerInfoSection(settings, cs),
              const SizedBox(height: Spacing.xl),
              _buildOrderSummary(cs, maxVisibleItems: 5, compact: false),
              const SizedBox(height: Spacing.xl),
              AppButton.filled(
                fullWidth: true,
                icon: Icons.receipt_long_outlined,
                label: 'Review Payment',
                size: AppButtonSize.large,
                onPressed: () => _goToReview(settings),
              ),
              const SizedBox(height: Spacing.lg),
              _buildSecureNote(cs),
            ],
          ),
        ),
      ],
    );
  }

  /// Subtle reassurance caption under the primary action, matching the
  /// "secure payment" footer of modern mobile payment screens without
  /// competing with the action above it.
  Widget _buildSecureNote(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: Spacing.xs),
        Text(
          'Secure payment via GCash',
          style: AppTypography.bodySmall(
            context,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  /// The amount must be the strongest visual element on the screen.
  ///
  /// It is displayed full-width, centered, in a themed surface so it is
  /// readable in both light and dark mode.
  Widget _buildTotalCard(ColorScheme cs) {
    return AppCard(
      color: cs.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total Due',
              style: AppTypography.bodyLarge(
                context,
              ).copyWith(color: cs.onPrimary.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: Spacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                CurrencyUtils.format(widget.total),
                style: AppTypography.displayMedium(
                  context,
                ).copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// QR code card: header, live decode status, the merchant QR itself and
  /// the scan instruction.
  ///
  /// The QR is displayed as a single, clearly bounded, tappable square sized
  /// from the available width so it stays the dominant element on phones
  /// without being stretched or cropped. It is the merchant's static QR from
  /// Payment Settings; it is *not* regenerated with customer or amount data.
  Widget _buildQrCard(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    final previewPath = settings.gcashQrPreviewPath;
    final displayPath = previewPath?.isNotEmpty == true ? previewPath : qrPath;
    final hasImage = displayPath != null && displayPath.isNotEmpty;
    final canConfigure = SessionManager().canEditBusinessSettings();
    final decodeAsync = qrPath != null && qrPath.isNotEmpty
        ? ref.watch(paymentQrDecodeProvider(qrPath))
        : null;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Scan to Pay',
                    style: AppTypography.titleSmallBold(context),
                  ),
                ),
                if (hasImage) _buildQrStatusChip(cs, decodeAsync),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (hasImage) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  // Fill most of the available width while keeping generous
                  // quiet-zone margins. 220–300 px covers small and large
                  // phones; the 320 px cap keeps tablet/desktop columns sane.
                  final qrSize =
                      (constraints.maxWidth * 0.78).clamp(220.0, 320.0);

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: qrSize),
                      child: AppPaymentQrPreview(
                        imagePath: displayPath,
                        onTap: () => _openQrViewer(displayPath),
                        maxHeight: qrSize,
                        embedded: true,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Open GCash and scan this QR code to complete the payment.',
                style: AppTypography.bodySmall(
                  context,
                ).copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              _buildMissingQrState(cs, canConfigure),
            ],
          ],
        ),
      ),
    );
  }

  /// Owner-only shortcut that appears when no QR is configured.
  Widget _buildConfigureQrButton(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    final previewPath = settings.gcashQrPreviewPath;
    final hasImage = (previewPath?.isNotEmpty == true) ||
        (qrPath != null && qrPath.isNotEmpty);
    if (hasImage || !SessionManager().canEditBusinessSettings()) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: AppButton.outlined(
        fullWidth: true,
        icon: Icons.settings_outlined,
        label: 'Configure GCash QR',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PaymentSettingsPage(),
            ),
          );
        },
      ),
    );
  }

  /// Live decode-status chip shown next to the Scan to Pay header.
  ///
  /// Reports exactly what happened to the QR image: decoding in progress,
  /// recognized payment QR, decoded-but-unidentified payload, or an
  /// unreadable image. Colors come from the semantic palette so the states
  /// read correctly in both light and dark mode.
  Widget _buildQrStatusChip(
    ColorScheme cs,
    AsyncValue<DecodedPaymentQr>? decodeAsync,
  ) {
    final brightness = Theme.of(context).brightness;

    if (decodeAsync == null || decodeAsync.isLoading) {
      return _statusChip(
        cs,
        icon: null,
        label: 'Reading QR…',
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurfaceVariant,
        showSpinner: true,
      );
    }

    final decoded = decodeAsync.value;
    final status = decoded?.status ?? PaymentQrDecodeStatus.unreadable;
    final hasDetails = decoded?.hasAnyDetails ?? false;

    return switch (status) {
      PaymentQrDecodeStatus.recognized when hasDetails => _statusChip(
          cs,
          icon: Icons.verified_outlined,
          label: 'Merchant details detected',
          background: AppSemanticColors.resolve(
            AppSemanticColors.successContainer,
            brightness,
          ),
          foreground: AppSemanticColors.resolve(
            AppSemanticColors.onSuccessContainer,
            brightness,
          ),
        ),
      PaymentQrDecodeStatus.recognized => _statusChip(
          cs,
          icon: Icons.check_circle_outline,
          label: 'Payment QR recognized',
          background: AppSemanticColors.resolve(
            AppSemanticColors.successContainer,
            brightness,
          ),
          foreground: AppSemanticColors.resolve(
            AppSemanticColors.onSuccessContainer,
            brightness,
          ),
        ),
      PaymentQrDecodeStatus.decodedUnparsed => _statusChip(
          cs,
          icon: Icons.qr_code,
          label: 'QR detected — details unavailable',
          background: cs.surfaceContainerHighest,
          foreground: cs.onSurfaceVariant,
        ),
      _ => _statusChip(
          cs,
          icon: Icons.warning_amber_rounded,
          label: 'Unable to read QR code',
          background: AppSemanticColors.resolve(
            AppSemanticColors.warningContainer,
            brightness,
          ),
          foreground: AppSemanticColors.resolve(
            AppSemanticColors.onWarningContainer,
            brightness,
          ),
        ),
    };
  }

  Widget _statusChip(
    ColorScheme cs, {
    required IconData? icon,
    required String label,
    required Color background,
    required Color foreground,
    bool showSpinner = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: foreground,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 14, color: foreground),
          const SizedBox(width: Spacing.xs),
          Text(
            label,
            style: AppTypography.labelSmall(context).copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Inline missing-QR state rendered inside the section card.
  ///
  /// Keeps the "no QR configured" message in the same visual section as the
  /// scan-to-pay header instead of a detached standalone card.
  Widget _buildMissingQrState(ColorScheme cs, bool canConfigure) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code, color: cs.onErrorContainer, size: 40),
          const SizedBox(height: Spacing.sm),
          Text(
            'GCash QR not configured',
            style: AppTypography.bodyMediumSemibold(
              context,
            ).copyWith(color: cs.onErrorContainer),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            canConfigure
                ? 'Upload the business GCash QR so customers can scan it.'
                : 'The Owner must upload the business GCash QR before customers can scan it.',
            style: AppTypography.bodySmall(
              context,
            ).copyWith(color: cs.onErrorContainer),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Payment details decoded from the QR payload (merchant name, mobile,
  /// network, encoded amount), with the configured store identity as a
  /// fallback when the QR does not encode merchant data.
  ///
  /// Only fields that actually exist are rendered — nothing is fabricated.
  /// QR-decoded values are marked "Detected from QR" so the cashier can tell
  /// them apart from configured store data and manually entered input.
  Widget _buildQrDetailsCard(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    if (qrPath == null || qrPath.isEmpty) return const SizedBox.shrink();

    final decodeAsync = ref.watch(paymentQrDecodeProvider(qrPath));
    // While decoding, the "Reading QR…" chip on the QR card already
    // communicates progress; keep the rest of the layout stable.
    if (decodeAsync.isLoading) return const SizedBox.shrink();

    final decoded = decodeAsync.value;
    final fromQr =
        decoded?.detectionSource == PaymentQrDetectionSource.qrPayload;

    final merchantName =
        fromQr ? decoded!.merchantName : null;
    final mobile = fromQr ? decoded!.mobileNumber : null;
    final account = fromQr ? decoded!.accountIdentifier : null;
    final network = fromQr ? decoded!.paymentNetwork : null;
    final qrAmount = fromQr ? decoded!.amount : null;
    final qrCurrency = fromQr ? decoded!.currencyCode : null;
    final qrReference = fromQr ? decoded!.qrReference : null;

    // Configured store identity is real data, not fabricated QR data — it
    // fills in only when the payload provides nothing for that field.
    final merchant = merchantName ??
        (settings.storeName.isNotEmpty ? settings.storeName : null);
    final phone =
        mobile ?? (settings.storePhone.isNotEmpty ? settings.storePhone : null);
    final showAccount = account != null && mobile == null;

    final amountMismatch = qrAmount != null &&
        (qrAmount - widget.total).abs() > 0.005;

    final hasAnyRow = merchant != null ||
        phone != null ||
        showAccount ||
        network != null ||
        qrAmount != null ||
        qrReference != null;
    if (!hasAnyRow && !amountMismatch) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg),
      child: AppCard(
        variant: AppCardVariant.filled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(
                    Icons.storefront_outlined,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Payment Details',
                    style: AppTypography.titleSmallBold(context),
                  ),
                ),
                if (fromQr && decoded!.hasMerchantInfo)
                  Text(
                    'Detected from QR',
                    style: AppTypography.labelSmall(context).copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (merchant != null)
              _buildDetailRow(cs, label: 'Merchant', value: merchant),
            if (phone != null)
              _buildDetailRow(cs, label: 'Mobile', value: phone),
            if (showAccount)
              _buildDetailRow(cs, label: 'Account', value: account),
            if (network != null)
              _buildDetailRow(cs, label: 'Network', value: network),
            if (qrAmount != null)
              _buildDetailRow(
                cs,
                label: 'Amount in QR',
                value: CurrencyUtils.format(
                  qrAmount,
                  currency: qrCurrency,
                ),
              ),
            if (qrReference != null)
              _buildDetailRow(cs, label: 'QR Reference', value: qrReference),
            if (amountMismatch) ...[
              const SizedBox(height: Spacing.sm),
              _buildAmountMismatchNote(cs, qrAmount, qrCurrency),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    ColorScheme cs, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: AppTypography.bodySmallSemibold(context),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Warning shown when the amount encoded in a fixed-amount QR does not
  /// match the POS transaction total. The POS total stays authoritative.
  Widget _buildAmountMismatchNote(
    ColorScheme cs,
    double qrAmount,
    String? currency,
  ) {
    final brightness = Theme.of(context).brightness;
    final background = AppSemanticColors.resolve(
      AppSemanticColors.warningContainer,
      brightness,
    );
    final foreground = AppSemanticColors.resolve(
      AppSemanticColors.onWarningContainer,
      brightness,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: foreground),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'This QR requests ${CurrencyUtils.format(qrAmount, currency: currency)} '
              'but the sale total is ${CurrencyUtils.format(widget.total)}. '
              'Ask the customer to pay the total shown above.',
              style: AppTypography.bodySmall(context).copyWith(
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openQrViewer(String qrPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppPaymentQrViewer(
          imagePath: qrPath,
          title: 'Scan to Pay',
          caption: 'Scan this GCash QR code to pay',
        ),
      ),
    );
  }

  /// Customer / payment information: customer name, reference number, and
  /// optional payment proof. Validation is driven by Payment Settings.
  ///
  /// The decoded QR data is intentionally NOT copied into these fields: the
  /// merchant QR identifies the payee (the store), never the customer. See
  /// [_buildQrDetailsCard] for the auto-detected merchant details.
  Widget _buildCustomerInfoSection(PaymentSettings settings, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          variant: AppCardVariant.filled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(
                      Icons.person_outline,
                      color: cs.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Customer / Payment Information',
                    style: AppTypography.titleSmallBold(context),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              if (settings.customerNameVisible) ...[
                AppTextFormField(
                  controller: _customerController,
                  label: _customerNameLabel(settings),
                  hint: 'Customer name',
                  prefixIcon: Icons.person_outline,
                  helperText: settings.customerNameRequired
                      ? 'A customer name is required to complete this payment.'
                      : 'Optional customer name for this transaction.',
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) => _validateCustomer(settings, value),
                ),
                const SizedBox(height: Spacing.lg),
              ],
              AppTextFormField(
                controller: _referenceController,
                label: settings.gcashReferenceRequired
                    ? 'GCash Reference Number *'
                    : 'GCash Reference Number',
                hint: 'Reference number',
                prefixIcon: Icons.numbers,
                helperText:
                    'Enter the reference number shown after completing the GCash payment.',
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                validator: (value) => _validateReference(settings, value),
                onFieldSubmitted: (_) => _goToReview(settings),
              ),
            ],
          ),
        ),
        if (settings.paymentProofVisible) ...[
          const SizedBox(height: Spacing.xl),
          AppCard(
            variant: AppCardVariant.filled,
            child: _buildProofPicker(settings, cs),
          ),
        ],
      ],
    );
  }

  /// Compact, scannable order summary.
  ///
  /// It confirms what is being paid for without competing with the amount,
  /// QR, or primary action.
  Widget _buildOrderSummary(
    ColorScheme cs, {
    int maxVisibleItems = 3,
    bool compact = false,
  }) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final visibleItems = cart.items.take(maxVisibleItems).toList();
    final hiddenCount = cart.items.length - visibleItems.length;

    return AppCard(
      variant: AppCardVariant.filled,
      child: Padding(
        padding: compact
            ? const EdgeInsets.all(Spacing.md)
            : const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: cs.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      'Order Summary',
                      style: AppTypography.titleSmallBold(context),
                    ),
                  ],
                ),
                Text(
                  '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                  style: AppTypography.bodySmall(
                    context,
                  ).copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            ...visibleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.product.name} × ${item.quantity}',
                        style: compact
                            ? AppTypography.bodySmall(context)
                            : AppTypography.bodyMedium(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Text(
                      CurrencyUtils.format(item.lineTotal),
                      style: AppTypography.bodyMedium(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  '+$hiddenCount more item${hiddenCount == 1 ? '' : 's'}',
                  style: AppTypography.bodySmall(
                    context,
                  ).copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProofPicker(PaymentSettings settings, ColorScheme cs) {
    final proofPath = _paymentProofPath;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppSemanticColors.resolve(
                  AppSemanticColors.infoContainer,
                  brightness,
                ),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(
                Icons.photo_camera_outlined,
                color: AppSemanticColors.resolve(
                  AppSemanticColors.info,
                  brightness,
                ),
                size: 18,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'Payment Proof',
              style: AppTypography.titleSmallBold(context),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          settings.paymentProofRequired
              ? 'Attach a clear photo of the GCash payment screen.'
              : 'Attach a photo of the GCash payment screen if needed.',
          style: AppTypography.bodySmall(
            context,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.md),
        if (proofPath != null) ...[
          _buildProofThumbnail(proofPath),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: AppButton.outlined(
                  fullWidth: true,
                  icon: Icons.camera_alt_outlined,
                  label: 'Retake',
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: AppButton.outlined(
                  fullWidth: true,
                  color: AppButtonColor.error,
                  icon: Icons.delete_outline,
                  label: 'Remove',
                  onPressed: _removeProof,
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: AppButton.outlined(
                  fullWidth: true,
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: AppButton.outlined(
                  fullWidth: true,
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
        if (settings.paymentProofRequired)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Payment proof is required',
              style: AppTypography.labelMedium(
                context,
              ).copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }

  Widget _buildProofThumbnail(String relativePath) {
    // AppImage resolves the stored path and shows a themed placeholder if
    // the file was deleted or corrupted instead of a bare broken-image icon.
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: AppImage(
        imagePath: relativePath,
        placeholderIcon: Icons.receipt_long_outlined,
        placeholderIconSize: 40,
        borderRadius: 12,
        fit: BoxFit.cover,
        cacheWidth: 1024,
        semanticLabel: 'Payment proof',
      ),
    );
  }

  Widget _buildReview(PaymentSettings settings, ColorScheme cs) {
    final needsVerification = ref
        .read(paymentVerificationServiceProvider)
        .requiresVerificationFor(
          operatorRole: SessionManager().currentUser?.role,
          paymentMethod: 'GCash',
          settings: settings,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = layoutClassFor(constraints.maxWidth).isCompact;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please review the payment details before completing.',
              style: AppTypography.bodyLarge(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            _buildTotalCard(cs),
            const SizedBox(height: Spacing.lg),
            if (isCompact)
              _buildCompactReviewBody(settings, cs, needsVerification)
            else
              _buildWideReviewBody(settings, cs, needsVerification),
            const SizedBox(height: Spacing.xl),
          ],
        );
      },
    );
  }

  Widget _buildCompactReviewBody(
    PaymentSettings settings,
    ColorScheme cs,
    bool needsVerification,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPaymentMethodCard(cs),
        const SizedBox(height: Spacing.lg),
        _buildPaymentDetailsCard(settings, cs),
        const SizedBox(height: Spacing.lg),
        _buildOrderSummary(cs, maxVisibleItems: 5),
        if (needsVerification) ...[
          const SizedBox(height: Spacing.lg),
          _buildVerificationCard(cs),
        ],
        const SizedBox(height: Spacing.xl),
        _buildReviewActions(settings),
      ],
    );
  }

  Widget _buildWideReviewBody(
    PaymentSettings settings,
    ColorScheme cs,
    bool needsVerification,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPaymentMethodCard(cs),
              const SizedBox(height: Spacing.lg),
              _buildOrderSummary(cs, maxVisibleItems: 5),
            ],
          ),
        ),
        const SizedBox(width: Spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPaymentDetailsCard(settings, cs),
              if (needsVerification) ...[
                const SizedBox(height: Spacing.lg),
                _buildVerificationCard(cs),
              ],
              const SizedBox(height: Spacing.xl),
              _buildReviewActions(settings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(ColorScheme cs) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(Icons.qr_code_2, color: cs.primary),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Method',
                    style: AppTypography.bodySmall(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    'GCash',
                    style: AppTypography.titleMediumBold(context),
                  ),
                ],
              ),
            ),
            Icon(Icons.check_circle, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDetailsCard(PaymentSettings settings, ColorScheme cs) {
    final customer = _customerController.text.trim();
    final reference = _referenceController.text.trim();
    final hasProof = _paymentProofPath != null;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Payment Details',
                  style: AppTypography.titleSmallBold(context),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            _buildReviewRow(
              label: 'Reference Number',
              value: reference.isEmpty ? 'Not provided' : reference,
              valueStyle: reference.isEmpty
                  ? AppTypography.bodyLarge(context).copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    )
                  : AppTypography.bodyLarge(context).copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
            ),
            if (settings.customerNameVisible) ...[
              const SizedBox(height: Spacing.md),
              _buildReviewRow(
                label: 'Customer',
                value: customer.isEmpty ? 'Not provided' : customer,
                valueStyle: customer.isEmpty
                    ? AppTypography.bodyLarge(context).copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      )
                    : AppTypography.bodyLarge(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              ),
            ],
            if (settings.paymentProofVisible) ...[
              const SizedBox(height: Spacing.md),
              _buildReviewRow(
                label: 'Payment Proof',
                value: _proofStatusLabel(settings, hasProof),
                icon: hasProof
                    ? Icons.check_circle
                    : (settings.paymentProofRequired
                        ? Icons.warning_amber_rounded
                        : Icons.photo_camera_outlined),
                iconColor: hasProof
                    ? cs.primary
                    : (settings.paymentProofRequired
                        ? cs.error
                        : cs.onSurfaceVariant),
                valueStyle: AppTypography.bodyLarge(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: hasProof
                      ? cs.primary
                      : (settings.paymentProofRequired
                          ? cs.error
                          : cs.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _proofStatusLabel(PaymentSettings settings, bool hasProof) {
    if (hasProof) return 'Attached';
    if (settings.paymentProofRequired) return 'Required';
    return 'Not provided';
  }

  Widget _buildReviewRow({
    required String label,
    required String value,
    TextStyle? valueStyle,
    IconData? icon,
    Color? iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall(
              context,
            ).copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: Spacing.md),
        if (icon != null) ...[
          Icon(icon, size: 20, color: iconColor ?? cs.onSurface),
          const SizedBox(width: Spacing.xs),
        ],
        Expanded(
          child: Text(
            value,
            style: valueStyle ?? AppTypography.bodyLarge(context),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationCard(ColorScheme cs) {
    return AppCard(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: cs.onSecondaryContainer),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'This GCash payment must be approved by the Owner before the sale is completed.',
                style: AppTypography.bodyMedium(
                  context,
                ).copyWith(color: cs.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewActions(PaymentSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton.outlined(
          fullWidth: true,
          icon: Icons.edit_outlined,
          label: 'Edit Details',
          onPressed: _isProcessing ? null : _goBackToDetails,
        ),
        const SizedBox(height: Spacing.md),
        AppButton.filled(
          fullWidth: true,
          icon: Icons.check_circle_outlined,
          label: 'Complete Payment',
          size: AppButtonSize.large,
          isLoading: _isProcessing,
          onPressed: () => _completeSale(settings),
        ),
      ],
    );
  }
}
