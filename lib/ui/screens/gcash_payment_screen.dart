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
  void initState() {
    super.initState();
  }

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
    if (settings.customerNameRequired) return 'Customer Name (required)';
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
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      AppDialogService.error(
        context,
        title: 'Empty Cart',
        message: 'The cart is empty. Add products before checkout.',
      );
      return;
    }

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
        return;
      }
      verifiedByUserId = result.value!.id;
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
        setState(() => _isProcessing = false);
        _isReviewing = false;
        AppDialogService.error(
          context,
          title: 'Invalid GCash Payment',
          message: e.message,
          details: e.details,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _isReviewing = false;
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
      appBar: AppHeader(
        title: _isReviewing ? 'Review Payment' : 'GCash Payment',
        showBackButton: true,
        onBackPressed: _isReviewing
            ? (_isProcessing ? null : _goBackToDetails)
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: _isReviewing
            ? _buildReview(settings, cs)
            : _buildDetails(settings, cs),
      ),
    );
  }

  Widget _buildDetails(PaymentSettings settings, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = layoutClassFor(constraints.maxWidth).isCompact;

        return Form(
          key: _formKey,
          child: isCompact
              ? _buildCompactDetailsBody(settings, cs)
              : _buildWideDetailsBody(settings, cs),
        );
      },
    );
  }

  Widget _buildCompactDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTotalCard(cs),
        const SizedBox(height: Spacing.lg),
        _buildMerchantQrSection(settings, cs),
        _buildMerchantInfoCard(settings, cs),
        const SizedBox(height: Spacing.xl),
        _buildOrderSummary(cs, maxVisibleItems: 2, compact: true),
        const SizedBox(height: Spacing.xl),
        if (settings.customerNameVisible) ...[
          AppTextFormField(
            controller: _customerController,
            label: _customerNameLabel(settings),
            prefixIcon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (value) => _validateCustomer(settings, value),
          ),
          const SizedBox(height: Spacing.lg),
        ],
        AppTextFormField(
          controller: _referenceController,
          label: 'GCash Reference Number',
          prefixIcon: Icons.numbers,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          validator: (value) => _validateReference(settings, value),
        ),
        const SizedBox(height: Spacing.lg),
        if (settings.paymentProofVisible) ...[
          Text(
            'Payment Proof',
            style: AppTypography.titleSmallBold(context),
          ),
          const SizedBox(height: Spacing.sm),
          _buildProofPicker(settings, cs),
          const SizedBox(height: Spacing.lg),
        ],
        AppButton.filled(
          fullWidth: true,
          icon: Icons.receipt_long_outlined,
          label: 'Review Payment',
          size: AppButtonSize.large,
          onPressed: () => _goToReview(settings),
        ),
      ],
    );
  }

  Widget _buildWideDetailsBody(PaymentSettings settings, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTotalCard(cs),
              const SizedBox(height: Spacing.lg),
              _buildOrderSummary(cs, maxVisibleItems: 5, compact: true),
            ],
          ),
        ),
        const SizedBox(width: Spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMerchantQrSection(settings, cs),
              _buildMerchantInfoCard(settings, cs),
              const SizedBox(height: Spacing.xl),
              if (settings.customerNameVisible) ...[
                AppTextFormField(
                  controller: _customerController,
                  label: _customerNameLabel(settings),
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) => _validateCustomer(settings, value),
                ),
                const SizedBox(height: Spacing.lg),
              ],
              AppTextFormField(
                controller: _referenceController,
                label: 'GCash Reference Number',
                prefixIcon: Icons.numbers,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                validator: (value) => _validateReference(settings, value),
              ),
              const SizedBox(height: Spacing.lg),
              if (settings.paymentProofVisible) ...[
                Text(
                  'Payment Proof',
                  style: AppTypography.titleSmallBold(context),
                ),
                const SizedBox(height: Spacing.sm),
                _buildProofPicker(settings, cs),
                const SizedBox(height: Spacing.lg),
              ],
              AppButton.filled(
                fullWidth: true,
                icon: Icons.receipt_long_outlined,
                label: 'Review Payment',
                size: AppButtonSize.large,
                onPressed: () => _goToReview(settings),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact recap of the cart so the cashier sees what the customer is
  /// paying for. The number of visible lines is configurable so the review
  /// screen can show a longer summary while the details screen stays compact.
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
                  'Order',
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

  Widget _buildTotalCard(ColorScheme cs) {
    return AppCard(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total Due',
              style: AppTypography.bodyLarge(
                context,
              ).copyWith(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: Spacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyUtils.format(widget.total),
                style: AppTypography.displayMedium(
                  context,
                ).copyWith(
                  color: cs.onPrimaryContainer,
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

  Widget _buildMerchantQrSection(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    final previewPath = settings.gcashQrPreviewPath;
    final displayPath = previewPath?.isNotEmpty == true ? previewPath : qrPath;
    final hasImage = displayPath != null && displayPath.isNotEmpty;
    final canConfigure = SessionManager().canEditBusinessSettings();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.qr_code_scanner, color: cs.primary, size: 20),
            const SizedBox(width: Spacing.sm),
            Text(
              'Scan to pay',
              style: AppTypography.titleSmallBold(context),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = constraints.maxWidth < 320
                ? constraints.maxWidth
                : 320.0;
            return AppPaymentQrPreview(
              imagePath: displayPath,
              onTap: hasImage ? () => _openQrViewer(displayPath) : null,
              maxHeight: qrSize,
              emptyTitle: 'GCash QR not configured',
              emptySubtitle: canConfigure
                  ? 'Upload the business GCash QR so customers can scan it.'
                  : 'The Owner must upload the business GCash QR before customers can scan it.',
            );
          },
        ),
        if (!hasImage && canConfigure) ...[
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: AppButton.outlined(
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
          ),
        ],
        const SizedBox(height: Spacing.md),
        Text(
          'Open your GCash app and scan the QR code.',
          style: AppTypography.bodySmall(
            context,
          ).copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildMerchantInfoCard(PaymentSettings settings, ColorScheme cs) {
    final storeName = settings.storeName;
    final storePhone = settings.storePhone;

    if (storeName.isEmpty && storePhone.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: cs.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (storeName.isNotEmpty)
                      Text(
                        storeName,
                        style: AppTypography.bodyLarge(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (storePhone.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        storePhone,
                        style: AppTypography.bodySmall(
                          context,
                        ).copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofPicker(PaymentSettings settings, ColorScheme cs) {
    final proofPath = _paymentProofPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (proofPath != null) ...[
          _buildProofThumbnail(proofPath),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Retake'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _removeProof,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
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
              ).copyWith(color: cs.onSurfaceVariant),
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
              'Please review the payment details before confirming.',
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
        _buildOrderSummary(cs, maxVisibleItems: 5),
        const SizedBox(height: Spacing.lg),
        _buildPaymentMethodCard(cs),
        const SizedBox(height: Spacing.lg),
        _buildPaymentDetailsCard(settings, cs),
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
        Expanded(child: _buildOrderSummary(cs, maxVisibleItems: 5)),
        const SizedBox(width: Spacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPaymentMethodCard(cs),
              const SizedBox(height: Spacing.lg),
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
          label: 'Confirm Payment',
          size: AppButtonSize.large,
          isLoading: _isProcessing,
          onPressed: () => _completeSale(settings),
        ),
      ],
    );
  }
}
