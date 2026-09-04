import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/screens/payment_settings_page.dart';
import 'package:pinoy_pos/ui/screens/payment_success_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
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

  Future<void> _completeSale() async {
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
      final success = await ref.read(salesServiceProvider).createSale(
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

        // Load the created sale to pass to the success screen.
        // The most recent sale by the current user is the one just created.
        final sales = await ref.read(salesServiceProvider).getSales();
        final sale = sales.isNotEmpty ? sales.first : null;

        if (!mounted) return;

        if (sale != null) {
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => PaymentSuccessScreen(sale: sale),
            ),
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
        showBackButton: !_isReviewing,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _isReviewing
            ? _buildReview(settings, cs)
            : _buildDetails(settings, cs),
      ),
    );
  }

  Widget _buildDetails(PaymentSettings settings, ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(cs),
          const SizedBox(height: 24),
          _buildMerchantQrSection(settings, cs),
          if (settings.customerNameVisible) ...[
            AppTextFormField(
              controller: _customerController,
              label: 'Customer Name',
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              validator: (value) => _validateCustomer(settings, value),
            ),
            const SizedBox(height: 16),
          ],
          AppTextFormField(
            controller: _referenceController,
            label: 'GCash Reference Number',
            prefixIcon: Icons.numbers,
            textCapitalization: TextCapitalization.characters,
            validator: (value) => _validateReference(settings, value),
          ),
          const SizedBox(height: 16),
          if (settings.paymentProofVisible) ...[
            Text(
              'Payment Proof',
              style: AppTypography.titleSmallBold(context),
            ),
            const SizedBox(height: 8),
            _buildProofPicker(settings, cs),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _goToReview(settings),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Review Payment'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(ColorScheme cs) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Due',
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
            Text(
              CurrencyUtils.format(widget.total),
              style: AppTypography.titleLargeBold(context)
                  .copyWith(color: cs.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantQrSection(PaymentSettings settings, ColorScheme cs) {
    final qrPath = settings.gcashQrImagePath;
    if (qrPath != null && qrPath.isNotEmpty) {
      return _buildMerchantQrCard(qrPath, cs);
    }
    return _buildMissingQrCard(cs);
  }

  Widget _buildMerchantQrCard(String qrPath, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.qr_code_scanner, color: cs.onPrimaryContainer),
                const SizedBox(height: 8),
                Text(
                  'Scan this GCash QR code to pay',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AppImage(
                      imagePath: qrPath,
                      placeholderIcon: Icons.qr_code,
                      fit: BoxFit.contain,
                      cacheWidth: null,
                      semanticLabel: 'GCash merchant QR code',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'After paying, enter the reference number below.',
                  style: TextStyle(color: cs.onPrimaryContainer),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMissingQrCard(ColorScheme cs) {
    final canConfigure = SessionManager().canEditBusinessSettings();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.qr_code, color: cs.onErrorContainer),
                const SizedBox(height: 8),
                Text(
                  'GCash QR not configured',
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  canConfigure
                      ? 'Upload the business GCash QR so customers can scan it.'
                      : 'The Owner must upload the business GCash QR before customers can scan it.',
                  style: TextStyle(color: cs.onErrorContainer),
                  textAlign: TextAlign.center,
                ),
                if (canConfigure) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaymentSettingsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Configure GCash QR'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProofPicker(PaymentSettings settings, ColorScheme cs) {
    final proofPath = _paymentProofPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (proofPath != null) ...[
          _buildProofThumbnail(proofPath),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Retake'),
                ),
              ),
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
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
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Payment proof is required',
              style: AppTypography.labelMedium(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProofThumbnail(String relativePath) {
    return FutureBuilder<File?>(
      future: ImageService().resolveImageFile(relativePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const SizedBox(
            height: 160,
            child: Center(child: Icon(Icons.broken_image)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  Widget _buildReview(PaymentSettings settings, ColorScheme cs) {
    final customer = _customerController.text.trim();
    final reference = _referenceController.text.trim();
    final hasProof = _paymentProofPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTotalCard(cs),
        const SizedBox(height: 24),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Method',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'GCash',
                  style: AppTypography.titleMediumBold(context),
                ),
                if (customer.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Customer',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(customer, style: AppTypography.bodyLarge(context)),
                ],
                const SizedBox(height: 12),
                Text(
                  'Reference Number',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  reference,
                  style: AppTypography.titleMediumBold(context)
                      .copyWith(color: cs.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Payment Proof',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  hasProof ? 'Attached' : 'None',
                  style: TextStyle(
                    color: hasProof ? cs.primary : cs.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (settings.verificationRequired)
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
                      'This payment requires owner/admin verification before it is treated as a completed sale.',
                      style: TextStyle(color: cs.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _goBackToDetails,
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LoadingButton(
                isLoading: _isProcessing,
                onPressed: _isProcessing ? null : _completeSale,
                label: 'Confirm Payment',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
