import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/dialogs/gcash_verification_dialog.dart';
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
  final _customerController = TextEditingController();
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

    // Enforce the verification policy before any sale is written. When the
    // operator (e.g. Staff) requires verification, an authorized verifier
    // must approve the payment at the till. The Owner's own sales are
    // exempt. Cancelling the dialog leaves the cart intact and creates no
    // sale.
    int? verifiedByUserId;
    final verificationService = ref.read(paymentVerificationServiceProvider);
    final operator = SessionManager().currentUser;
    final needsVerification = verificationService.requiresVerificationFor(
      operatorRole: operator?.role,
      paymentMethod: 'GCash',
      settings: settings,
    );

    if (needsVerification) {
      final result = await showGcashVerificationDialog(
        context,
        total: widget.total,
        operatorName: operator?.fullName ?? 'Staff',
        settings: settings,
      );

      if (!mounted) return;
      if (result == null || !result.isSaved || result.value == null) {
        // Verification was cancelled — abort the sale. The cart, form and
        // attached proof remain untouched so the operator can retry.
        setState(() => _isProcessing = false);
        return;
      }
      verifiedByUserId = result.value!.id;
    }

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
            verifiedByUserId: verifiedByUserId,
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
  /// Header → Amount → Scan to Pay / QR → Instructions → Customer / Reference
  /// → Proof (if enabled) → Order Summary → Review Payment.
  Widget _buildCompactDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTotalCard(cs),
        const SizedBox(height: Spacing.lg),
        _buildMerchantQrSection(settings, cs),
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

  /// Tablet / desktop layout: payment context on the left, required inputs and
  /// confirmation on the right. The hierarchy is preserved; the columns only
  /// make better use of available width.
  Widget _buildWideDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTotalCard(cs),
              const SizedBox(height: Spacing.lg),
              _buildMerchantQrSection(settings, cs),
            ],
          ),
        ),
        const SizedBox(width: Spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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

  /// QR code section: merchant QR, scan instructions, and merchant identity
  /// grouped into a single card so the amount → QR → instructions flow reads
  /// as one payment context.
  ///
  /// The QR is displayed as a single, clearly bounded, tappable square. It is
  /// the merchant's static QR from Payment Settings; it is *not* regenerated
  /// with customer name or amount data.
  Widget _buildMerchantQrSection(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    final previewPath = settings.gcashQrPreviewPath;
    final displayPath = previewPath?.isNotEmpty == true ? previewPath : qrPath;
    final hasImage = displayPath != null && displayPath.isNotEmpty;
    final canConfigure = SessionManager().canEditBusinessSettings();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: cs.primary, size: 20),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Scan to Pay',
                        style: AppTypography.titleSmallBold(context),
                      ),
                    ),
                    _buildQrBadge(cs),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                if (hasImage) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact =
                          layoutClassFor(constraints.maxWidth).isCompact;
                      final maxDimension = isCompact ? 220.0 : 280.0;
                      final qrSize =
                          (constraints.maxWidth * (isCompact ? 0.55 : 0.5))
                              .clamp(180.0, maxDimension);

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
                    'Open GCash and scan this QR code.',
                    style: AppTypography.bodySmall(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  _buildMerchantInfoRow(settings, cs),
                ] else ...[
                  _buildMissingQrState(cs, canConfigure),
                ],
              ],
            ),
          ),
        ),
        if (!hasImage && canConfigure) ...[
          const SizedBox(height: Spacing.md),
          AppButton.outlined(
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
        ],
      ],
    );
  }

  /// Small "QR Payment" badge shown on the right of the Scan to Pay header,
  /// matching the payment-method badge used by modern payment sheets.
  Widget _buildQrBadge(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 14,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            'QR Payment',
            style: AppTypography.labelSmall(context).copyWith(
              color: cs.onSecondaryContainer,
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

  /// Compact merchant identity shown under the QR, separated by a divider.
  ///
  /// This keeps the merchant visible without consuming the vertical space of
  /// a standalone card and without duplicating information elsewhere.
  Widget _buildMerchantInfoRow(PaymentSettings settings, ColorScheme cs) {
    final storeName = settings.storeName;
    final storePhone = settings.storePhone;

    if (storeName.isEmpty && storePhone.isEmpty) {
      return const SizedBox.shrink();
    }

    final label = [
      if (storeName.isNotEmpty) storeName,
      if (storePhone.isNotEmpty) storePhone,
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Spacing.md),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: Spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storefront_outlined,
              color: cs.primary,
              size: 18,
            ),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.bodySmallSemibold(context),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ],
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
  Widget _buildCustomerInfoSection(PaymentSettings settings, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer / Payment Information',
          style: AppTypography.titleSmallBold(context),
        ),
        const SizedBox(height: Spacing.md),
        if (settings.customerNameVisible) ...[
          AppTextFormField(
            controller: _customerController,
            label: _customerNameLabel(settings),
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
          prefixIcon: Icons.numbers,
          helperText:
              'Enter the reference number shown after completing the GCash payment.',
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          validator: (value) => _validateReference(settings, value),
          onFieldSubmitted: (_) => _goToReview(settings),
        ),
        if (settings.paymentProofVisible) ...[
          const SizedBox(height: Spacing.lg),
          _buildProofPicker(settings, cs),
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
                Text(
                  'Order Summary',
                  style: AppTypography.titleSmallBold(context),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Proof',
          style: AppTypography.titleSmallBold(context),
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
            Text(
              'Payment Details',
              style: AppTypography.titleSmallBold(context),
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
