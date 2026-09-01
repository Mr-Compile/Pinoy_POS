import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/payment_proof_provider.dart';
import 'package:pinoy_pos/providers/receipt_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';
import 'package:pinoy_pos/ui/screens/payment_proof_viewer_screen.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final Sale? sale;
  final int? saleId;

  const ReceiptScreen({
    super.key,
    this.sale,
    this.saleId,
  }) : assert(sale != null || saleId != null);

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _isExporting = false;
  bool _isExportingProof = false;
  bool _isLoading = false;
  bool _notFound = false;
  Sale? _loadedSale;
  final Map<String, Future<PaymentProofInfo?>> _proofFutures = {};

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
      MaterialPageRoute(
        builder: (_) => PaymentProofViewerScreen(sale: _sale),
      ),
    );
  }

  Future<void> _downloadPaymentProof(ReceiptViewData receipt) async {
    setState(() => _isExportingProof = true);
    try {
      final paymentProofService = ref.read(paymentProofServiceProvider);
      final saved = await paymentProofService.exportPaymentProofFromPath(
        receipt.paymentProofPath,
        receipt.saleId,
      );

      if (mounted) {
        setState(() => _isExportingProof = false);
        if (saved != null) {
          await AppDialogService.success(
            context,
            title: 'Payment Proof Saved',
            message: 'Saved to $saved',
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
          message: 'Unable to export payment proof: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(
          title: 'Receipt',
          showBackButton: true,
        ),
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

    return Scaffold(
      appBar: AppHeader(
        title: 'Receipt',
        showBackButton: true,
      ),
      body: receiptAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          title: 'Error',
          message: 'Failed to load receipt: $e',
          onRetry: () => ref.invalidate(receiptViewDataProvider(_saleId)),
        ),
        data: (receipt) {
          if (receipt == null) {
            return const ErrorState(
              title: 'Not Found',
              message: 'The receipt could not be found or you do not have permission to view it.',
            );
          }
          return _buildReceipt(receipt);
        },
      ),
    );
  }

  Widget _buildReceipt(ReceiptViewData receipt) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStoreHeader(receipt, cs),
              const SizedBox(height: 16),
              _buildTransactionHeader(receipt, cs),
              const SizedBox(height: 16),
              _buildItemsCard(receipt),
              const SizedBox(height: 16),
              _buildTotalsCard(receipt),
              const SizedBox(height: 16),
              _buildPaymentCard(receipt),
              if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildNotesCard(receipt),
              ],
              const SizedBox(height: 16),
              _buildFooterCard(receipt, cs),
              const SizedBox(height: 24),
              _buildActions(receipt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreHeader(ReceiptViewData receipt, ColorScheme cs) {
    return AppCard(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              receipt.storeName,
              style: AppTypography.titleMediumBold(context)
                  .copyWith(color: cs.onPrimaryContainer),
              textAlign: TextAlign.center,
            ),
            if (receipt.storeAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                receipt.storeAddress,
                style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            if (receipt.storePhone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Contact: ${receipt.storePhone}',
                style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionHeader(ReceiptViewData receipt, ColorScheme cs) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'OFFICIAL RECEIPT',
              style: AppTypography.titleSmallBold(context).copyWith(color: cs.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Receipt #${receipt.receiptNumber}',
              style: AppTypography.titleMediumBold(context),
            ),
            const SizedBox(height: 4),
            Text(
              receipt.date.toLocal().toString().split('.')[0],
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'Cashier: ${receipt.cashierName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Item', style: Theme.of(context).textTheme.titleSmall),
                Text('Total', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(),
            ...receipt.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.formattedTotal(receipt.currency),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity} x ${item.formattedUnitPrice(receipt.currency)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildValueRow('Subtotal', receipt.formattedSubtotal()),
            if (receipt.discount > 0)
              _buildValueRow('Discount', receipt.formattedDiscount()),
            const Divider(),
            _buildValueRow('TOTAL', receipt.formattedTotal(), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildValueRow('Payment Method', receipt.paymentMethod),
            if (receipt.cashReceived > 0)
              _buildValueRow('Amount Paid', receipt.formattedCashReceived()),
            if (receipt.change > 0)
              _buildValueRow('Change', receipt.formattedChange()),
            if (receipt.referenceNumber != null &&
                receipt.referenceNumber!.isNotEmpty)
              _buildValueRow('Reference', receipt.referenceNumber!),
            if (receipt.customerName != null &&
                receipt.customerName!.isNotEmpty)
              _buildValueRow('Customer', receipt.customerName!),
            _buildValueRow('Status', receipt.statusLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(receipt.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterCard(ReceiptViewData receipt, ColorScheme cs) {
    return AppCard(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (receipt.receiptFooter != null &&
                receipt.receiptFooter!.isNotEmpty)
              Text(
                receipt.receiptFooter!,
                style: TextStyle(color: cs.onSecondaryContainer),
                textAlign: TextAlign.center,
              ),
            if (receipt.receiptFooter != null &&
                receipt.receiptFooter!.isNotEmpty)
              const SizedBox(height: 8),
            Text(
              'Thank you!',
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: isTotal
                  ? AppTypography.titleMediumBold(context)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: isTotal
                ? AppTypography.titleMediumBold(context)
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ReceiptViewData receipt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (receipt.paymentProofPath != null &&
            receipt.paymentProofPath!.isNotEmpty) ...[
          FutureBuilder<PaymentProofInfo?>(
            future: _proofFutures.putIfAbsent(
              receipt.paymentProofPath!,
              () => ref
                  .read(paymentProofServiceProvider)
                  .resolveProofFromPath(receipt.paymentProofPath),
            ),
            builder: (context, snapshot) {
              final info = snapshot.data;
              final hasProof = info != null;
              final isPdf = info?.isPdf ?? false;
              final icon =
                  isPdf ? Icons.picture_as_pdf : Icons.image_outlined;
              final label = isPdf ? 'View PDF' : 'View Payment Proof';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: hasProof ? () => _viewPaymentProof(receipt) : null,
                    icon: Icon(icon),
                    label: Text(label),
                  ),
                  const SizedBox(height: 12),
                  LoadingButton(
                    isLoading: _isExportingProof,
                    onPressed: _isExportingProof
                        ? null
                        : () => _downloadPaymentProof(receipt),
                    label: 'Download Payment Proof',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        LoadingButton(
          isLoading: _isExporting,
          onPressed: _isExporting ? null : () => _downloadPdf(receipt),
          label: 'Download as PDF',
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SaleDetailScreen(sale: _sale),
              ),
            );
          },
          child: const Text('View Sale Details'),
        ),
      ],
    );
  }
}