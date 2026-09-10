import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/payment_proof_provider.dart';
import 'package:pinoy_pos/providers/receipt_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/payment_proof_viewer_screen.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final Sale? sale;
  final int? saleId;

  const ReceiptScreen({super.key, this.sale, this.saleId})
    : assert(sale != null || saleId != null);

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _isSharing = false;
  bool _isExporting = false;
  bool _isExportingProof = false;
  bool _isLoading = false;
  bool _notFound = false;
  Sale? _loadedSale;

  Sale get _sale => widget.sale ?? _loadedSale!;
  int get _saleId => _sale.id!;

  @override
  void initState() {
    super.initState();
    if (widget.sale == null && widget.saleId != null) {
      _loadSale(widget.saleId!);
    }
  }

  Future<void> _loadSale(int id) async {
    setState(() => _isLoading = true);
    try {
      final salesService = ref.read(salesServiceProvider);
      final sale = await salesService.getSaleById(id);
      if (mounted) {
        setState(() {
          _loadedSale = sale;
          _notFound = sale == null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _shareReceipt(ReceiptViewData receipt) async {
    setState(() => _isSharing = true);

    try {
      final receiptService = ref.read(receiptServiceProvider);
      final bytes = await receiptService.generateReceiptPdf(receipt);
      final fileName = receiptService.buildFileName(receipt);

      final savedPath = await receiptService.saveReceiptToAppDocuments(
        bytes,
        fileName: fileName,
      );

      if (mounted) {
        setState(() => _isSharing = false);
        if (savedPath != null) {
          await AppDialogService.success(
            context,
            title: 'Receipt Ready',
            message: 'The receipt has been saved and is ready to share:',
            details: savedPath,
          );
        } else {
          AppDialogService.error(
            context,
            title: 'Share Failed',
            message: 'Unable to prepare the receipt for sharing.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSharing = false);
        AppDialogService.error(
          context,
          title: 'Share Failed',
          message: 'Unable to prepare the receipt: $e',
        );
      }
    }
  }

  Future<void> _downloadPdf(ReceiptViewData receipt) async {
    setState(() => _isExporting = true);

    try {
      final receiptService = ref.read(receiptServiceProvider);
      final bytes = await receiptService.generateReceiptPdf(receipt);
      final fileName = receiptService.buildFileName(receipt);

      final savedPath = await receiptService.saveReceiptToFile(
        bytes,
        dialogTitle: 'Save Receipt',
        fileName: fileName,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        if (savedPath != null) {
          await AppDialogService.success(
            context,
            title: 'Receipt Saved',
            message: 'PDF saved to $savedPath',
          );
        } else {
          AppDialogService.error(
            context,
            title: 'Download Cancelled',
            message: 'No save location selected.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        AppDialogService.error(
          context,
          title: 'Download Failed',
          message: 'Unable to save the receipt: $e',
        );
      }
    }
  }

  Future<void> _viewPaymentProof(ReceiptViewData receipt) async {
    if (receipt.paymentProofPath == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentProofViewerScreen(sale: _sale)),
    );
  }

  Future<void> _downloadGcashProofImage(ReceiptViewData receipt) async {
    setState(() => _isExportingProof = true);
    try {
      final paymentProofService = ref.read(paymentProofServiceProvider);
      final saved = await paymentProofService.exportGcashProofAsImageFromPath(
        receipt.paymentProofPath,
        receipt.saleId,
      );

      if (mounted) {
        setState(() => _isExportingProof = false);
        if (saved != null) {
          await AppDialogService.success(
            context,
            title: 'Image Saved',
            message: 'GCash proof image saved to $saved',
          );
        } else {
          AppDialogService.error(
            context,
            title: 'Download Cancelled',
            message: 'No save location selected.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExportingProof = false);
        AppDialogService.error(
          context,
          title: 'Download Failed',
          message: 'Unable to save the GCash proof image: $e',
        );
      }
    }
  }

  void _viewSaleDetails() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: _sale)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Receipt', showBackButton: true),
        body: LoadingState(),
      );
    }

    if (_notFound || _saleId <= 0) {
      return Scaffold(
        appBar: const AppHeader(
          title: 'Receipt Not Found',
          showBackButton: true,
        ),
        body: ErrorState(
          title: 'Receipt Not Found',
          message: 'The requested receipt could not be found.',
          onPrimaryAction: () => Navigator.of(context).pop(),
          primaryActionLabel: 'Back',
        ),
      );
    }

    final receiptAsync = ref.watch(receiptViewDataProvider(_saleId));

    return receiptAsync.when(
      loading: () => const Scaffold(
        appBar: AppHeader(title: 'Receipt', showBackButton: true),
        body: LoadingState(),
      ),
      error: (e, _) => Scaffold(
        appBar: const AppHeader(title: 'Receipt', showBackButton: true),
        body: ErrorState(
          title: 'Error',
          message: 'Failed to load receipt: $e',
          onRetry: () => ref.invalidate(receiptViewDataProvider(_saleId)),
        ),
      ),
      data: (receipt) {
        if (receipt == null) {
          return const Scaffold(
            appBar: AppHeader(title: 'Receipt Not Found', showBackButton: true),
            body: ErrorState(
              title: 'Not Found',
              message:
                  'The receipt could not be found or you do not have permission to view it.',
            ),
          );
        }
        return _buildReceipt(receipt);
      },
    );
  }

  Widget _buildReceipt(ReceiptViewData receipt) {
    return Scaffold(
      appBar: AppHeader(
        title: 'Receipt',
        subtitle: receipt.receiptNumber,
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'View Sale Details',
            onPressed: _viewSaleDetails,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReceiptCard(receipt),
                const SizedBox(height: Spacing.md),
                _buildActions(receipt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard(ReceiptViewData receipt) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd hh:mm a');

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            receipt.storeName,
            style: AppTypography.titleMediumBold(
              context,
            ).copyWith(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          if (receipt.storeAddress.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              receipt.storeAddress,
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (receipt.storePhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Contact: ${receipt.storePhone}',
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Spacing.lg),
          const _DashedDivider(),
          const SizedBox(height: Spacing.lg),
          for (final item in receipt.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${item.productName} x${item.quantity}',
                      style: AppTypography.bodyMedium(context),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    CurrencyUtils.format(
                      item.totalPrice,
                      currency: receipt.currency,
                    ),
                    style: AppTypography.bodyMedium(context),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Spacing.sm),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: AppTypography.titleMediumBold(
                    context,
                  ).copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  CurrencyUtils.format(
                    receipt.total,
                    currency: receipt.currency,
                  ),
                  style: AppTypography.titleMediumBold(
                    context,
                  ).copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          _buildMetaSection(receipt, dateFormat),
          const SizedBox(height: Spacing.lg),
          Text(
            receipt.receiptFooter ?? 'Thank you, please come again!',
            style: AppTypography.bodySmall(
              context,
            ).copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaSection(ReceiptViewData receipt, DateFormat dateFormat) {
    final rows = <Widget>[
      _buildMetaRow('Payment', receipt.paymentMethod),
      _buildMetaRow('Cashier', receipt.cashierName),
      if (receipt.customerName != null && receipt.customerName!.isNotEmpty)
        _buildMetaRow('Customer', receipt.customerName!),
      _buildMetaRow('Date', dateFormat.format(receipt.date.toLocal())),
      _buildMetaRow('Receipt #', receipt.receiptNumber),
      _buildMetaRow('Status', receipt.statusLabel),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _buildMetaRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: AppTypography.bodySmall(
            context,
          ).copyWith(color: cs.onSurfaceVariant, height: 1.6),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ReceiptViewData receipt) {
    final canViewEvidence = ref
        .read(authStateProvider.notifier)
        .hasPermission('view_payment_evidence');

    final hasProof =
        receipt.paymentProofPath != null &&
        receipt.paymentProofPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton.outlined(
                isLoading: _isSharing,
                onPressed: _isSharing ? null : () => _shareReceipt(receipt),
                icon: Icons.share,
                label: 'Share',
                fullWidth: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton.filled(
                isLoading: _isExporting,
                onPressed: _isExporting ? null : () => _downloadPdf(receipt),
                icon: Icons.download,
                label: 'Download',
                fullWidth: true,
              ),
            ),
          ],
        ),
        if (canViewEvidence && hasProof) ...[
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton.outlined(
                  onPressed: () => _viewPaymentProof(receipt),
                  icon: Icons.image_outlined,
                  label: 'View Image',
                  fullWidth: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton.outlined(
                  isLoading: _isExportingProof,
                  onPressed: _isExportingProof
                      ? null
                      : () => _downloadGcashProofImage(receipt),
                  icon: Icons.download,
                  label: 'Download Image',
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(color: color),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    var startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
