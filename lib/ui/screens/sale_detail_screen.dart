import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/payment_proof_provider.dart';
import 'package:pinoy_pos/providers/receipt_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';

import 'package:pinoy_pos/services/payment_proof_service.dart';
import 'package:pinoy_pos/ui/screens/payment_proof_viewer_screen.dart';
import 'package:pinoy_pos/ui/screens/receipt_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  final Sale? sale;
  final int? saleId;

  const SaleDetailScreen({
    super.key,
    this.sale,
    this.saleId,
  }) : assert(sale != null || saleId != null);

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _isProcessing = false;
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

  Future<void> _confirmPayment() async {
    setState(() => _isProcessing = true);
    try {
      final salesService = ref.read(salesServiceProvider);
      final success = await salesService.confirmGcashPayment(_saleId);
      if (mounted) {
        setState(() => _isProcessing = false);
        if (success) {
          await AppDialogService.success(
            context,
            title: 'Payment Confirmed',
            message: 'The GCash payment has been confirmed.',
          );
          ref.invalidate(receiptViewDataProvider(_saleId));
        } else {
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Unable to confirm payment.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to confirm payment.',
        );
      }
    }
  }

  Future<void> _rejectPayment() async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Reject GCash Payment?',
      message: 'This will cancel the sale and restore inventory.',
      confirmLabel: 'Reject',
      destructive: true,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final salesService = ref.read(salesServiceProvider);
      final success = await salesService.rejectGcashPayment(_saleId);
      if (mounted) {
        setState(() => _isProcessing = false);
        if (success) {
          await AppDialogService.success(
            context,
            title: 'Payment Rejected',
            message: 'The GCash payment has been rejected and stock restored.',
          );
          if (mounted) Navigator.of(context).pop();
        } else {
          AppDialogService.error(
            context,
            title: 'Error',
            message: 'Unable to reject payment.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to reject payment.',
        );
      }
    }
  }

  Future<void> _viewReceipt() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(sale: _sale),
      ),
    );
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

  Future<void> _downloadPaymentProof() async {
    setState(() => _isExportingProof = true);
    try {
      final paymentProofService = ref.read(paymentProofServiceProvider);
      final saved = await paymentProofService.exportPaymentProof(_sale);

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

  Future<void> _viewPaymentProof() async {
    if (_sale.paymentProofPath == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentProofViewerScreen(sale: _sale),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(
          title: 'Sale Details',
          showBackButton: true,
        ),
        body: LoadingState(),
      );
    }

    if (_notFound || _saleId <= 0) {
      return Scaffold(
        appBar: const AppHeader(
          title: 'Sale Not Found',
          showBackButton: true,
        ),
        body: ErrorState(
          title: 'Sale Not Found',
          message: 'The requested sale could not be found.',
          onPrimaryAction: () => Navigator.of(context).pop(),
          primaryActionLabel: 'Back',
        ),
      );
    }

    final receiptAsync = ref.watch(receiptViewDataProvider(_saleId));
    final authNotifier = ref.read(authStateProvider.notifier);
    final canVerify = authNotifier.hasPermission('verify_payments');
    final canViewEvidence =
        authNotifier.hasPermission('view_payment_evidence');

    return Scaffold(
      appBar: AppHeader(
        title: 'Sale #${_sale.receiptNumber ?? _sale.id}',
        showBackButton: true,
      ),
      body: receiptAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          title: 'Error',
          message: 'Failed to load sale details: $e',
          onRetry: () =>
              ref.invalidate(receiptViewDataProvider(_saleId)),
        ),
        data: (receipt) {
          if (receipt == null) {
            return const ErrorState(
              title: 'Not Found',
              message: 'The sale could not be found or you do not have permission to view it.',
            );
          }
          return _buildBody(receipt, canVerify, canViewEvidence);
        },
      ),
    );
  }

  Widget _buildBody(
      ReceiptViewData receipt, bool canVerify, bool canViewEvidence) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(receipt, cs, canVerify),
              const SizedBox(height: 16),
              _buildAmountCard(receipt, cs),
              const SizedBox(height: 16),
              _buildItemsCard(receipt),
              const SizedBox(height: 16),
              _buildPaymentCard(receipt),
              if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildNotesCard(receipt),
              ],
              if (canViewEvidence &&
                  receipt.paymentProofPath != null &&
                  receipt.paymentProofPath!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildProofCard(receipt),
              ],
              const SizedBox(height: 24),
              _buildActions(receipt, canVerify),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
      ReceiptViewData receipt, ColorScheme cs, bool canVerify) {
    final statusColor = _statusColor(receipt.paymentStatus, cs);
    final statusIcon = _statusIcon(receipt.paymentStatus);

    return AppCard(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sale #${receipt.receiptNumber}',
                        style: AppTypography.titleMediumBold(context)
                            .copyWith(color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        receipt.date.toLocal().toString().split('.')[0],
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      Text(
                        'Cashier: ${receipt.cashierName}',
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(statusIcon, size: 16, color: statusColor),
                  label: Text(
                    receipt.statusLabel,
                    style: AppTypography.bodySmall(context)
                        .copyWith(color: statusColor),
                  ),
                  side: BorderSide(color: statusColor),
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                ),
              ],
            ),
            if (receipt.paymentStatus == 'pending' && canVerify) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LoadingButton(
                      isLoading: _isProcessing,
                      onPressed: _confirmPayment,
                      label: 'Confirm',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LoadingButton(
                      isLoading: _isProcessing,
                      onPressed: _rejectPayment,
                      label: 'Reject',
                      isDanger: true,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard(ReceiptViewData receipt, ColorScheme cs) {
    return AppCard(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              receipt.formattedTotal(),
              style: AppTypography.headlineSmallSemibold(context)
                  .copyWith(color: cs.primary),
            ),
            if (receipt.cashReceived > 0 || receipt.change > 0) ...[
              const SizedBox(height: 8),
              _buildValueRow('Amount Paid', receipt.formattedCashReceived()),
              _buildValueRow('Change', receipt.formattedChange()),
            ],
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
            Text(
              'Items',
              style: AppTypography.titleSmallBold(context),
            ),
            const SizedBox(height: 8),
            ...receipt.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: AppTypography.titleSmall(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.formattedTotal(receipt.currency),
                            style: AppTypography.titleSmallBold(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity} x ${item.formattedUnitPrice(receipt.currency)}',
                        style: AppTypography.bodySmall(context).copyWith(
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

  Widget _buildPaymentCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment',
              style: AppTypography.titleSmallBold(context),
            ),
            const SizedBox(height: 8),
            _buildValueRow('Method', receipt.paymentMethod),
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
            Text(
              'Notes',
              style: AppTypography.titleSmallBold(context),
            ),
            const SizedBox(height: 8),
            Text(receipt.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildProofCard(ReceiptViewData receipt) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Proof',
              style: AppTypography.titleSmallBold(context),
            ),
            const SizedBox(height: 8),
            FutureBuilder<PaymentProofInfo?>(
              future: _proofFutures.putIfAbsent(
                receipt.paymentProofPath!,
                () => ref
                    .read(paymentProofServiceProvider)
                    .resolveProofFromPath(receipt.paymentProofPath),
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final info = snapshot.data;
                if (info == null) {
                  return const Text('Unable to load payment proof.');
                }

                if (info.isImage) {
                  return GestureDetector(
                    onTap: _viewPaymentProof,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        info.file,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox(
                            height: 120,
                            child: Center(
                              child: Text('Unable to display this image.'),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }

                if (info.isPdf) {
                  return ListTile(
                    leading: const Icon(Icons.picture_as_pdf),
                    title: Text(info.fileType?.label ?? 'PDF Document'),
                    subtitle: Text(info.originalName ?? 'Unknown file'),
                    onTap: _viewPaymentProof,
                  );
                }

                return const Text('Unsupported payment proof type.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ReceiptViewData receipt, bool canVerify) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _viewReceipt,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View Receipt'),
        ),
        const SizedBox(height: 12),
        LoadingButton(
          isLoading: _isExporting,
          onPressed: _isExporting ? null : () => _downloadPdf(receipt),
          label: 'Download PDF',
        ),
        const SizedBox(height: 12),
        if (receipt.paymentProofPath != null &&
            receipt.paymentProofPath!.isNotEmpty) ...[
          OutlinedButton.icon(
            onPressed: _viewPaymentProof,
            icon: const Icon(Icons.image_outlined),
            label: const Text('View Payment Proof'),
          ),
          const SizedBox(height: 12),
          LoadingButton(
            isLoading: _isExportingProof,
            onPressed: _isExportingProof ? null : _downloadPaymentProof,
            label: 'Download Payment Proof',
          ),
        ],
      ],
    );
  }

  Widget _buildValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    return switch (status) {
      'confirmed' => cs.primary,
      'pending' => cs.tertiary,
      'cancelled' || 'refunded' => cs.error,
      _ => cs.outline,
    };
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'confirmed' => Icons.check_circle,
      'pending' => Icons.hourglass_empty,
      'cancelled' || 'refunded' => Icons.cancel,
      _ => Icons.help,
    };
  }
}