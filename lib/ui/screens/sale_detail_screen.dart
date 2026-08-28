import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
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
  final Sale sale;

  const SaleDetailScreen({super.key, required this.sale});

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  List<SaleItem> _items = [];
  Map<int, String> _productNames = {};
  Settings? _storeInfo;
  bool _isLoading = true;
  String? _error;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final salesService = ref.read(salesServiceProvider);
      final productService = ref.read(productServiceProvider);
      final reportService = ref.read(reportServiceProvider);

      // getSaleItems enforces ownership for Staff at the service layer.
      final items = await salesService.getSaleItems(widget.sale.id!);

      final names = <int, String>{};
      for (final item in items) {
        final product = await productService.getProductById(item.productId);
        if (product != null) {
          names[item.productId] = product.name;
        }
      }

      final storeInfo = await reportService.getStoreInfo();

      if (mounted) {
        setState(() {
          _items = items;
          _productNames = names;
          _storeInfo = storeInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load sale items';
        });
      }
    }
  }

  Future<void> _confirmPayment() async {
    setState(() => _isProcessing = true);
    try {
      final salesService = ref.read(salesServiceProvider);
      final success =
          await salesService.confirmGcashPayment(widget.sale.id!);
      if (mounted) {
        setState(() => _isProcessing = false);
        if (success) {
          await AppDialogService.success(
            context,
            title: 'Payment Confirmed',
            message: 'The GCash payment has been confirmed.',
          );
          _loadItems();
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
      final success =
          await salesService.rejectGcashPayment(widget.sale.id!);
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          sale: widget.sale,
          items: _items,
          productNames: _productNames,
        ),
      ),
    );
  }

  Future<void> _viewProof() async {
    if (widget.sale.paymentProofPath == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentProofViewerScreen(sale: widget.sale),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canVerify = authNotifier.hasPermission('verify_payments');
    final canViewEvidence =
        authNotifier.hasPermission('view_payment_evidence');

    return Scaffold(
      appBar: AppHeader(
        title: 'Receipt #${widget.sale.receiptNumber ?? widget.sale.id}',
        showBackButton: true,
      ),
      body: _isLoading
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  title: 'Error',
                  message: _error,
                  onRetry: _loadItems,
                )
              : _items.isEmpty
                  ? const ErrorState(
                      title: 'Access Denied',
                      message: 'You do not have permission to view this sale.',
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStoreHeader(),
                          const SizedBox(height: 16),
                          _buildStatusCard(canVerify),
                          const SizedBox(height: 16),
                          _buildItemsCard(),
                          const SizedBox(height: 16),
                          _buildPaymentCard(),
                          if (widget.sale.notes != null &&
                              widget.sale.notes!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildNotesCard(),
                          ],
                          if (canViewEvidence &&
                              widget.sale.paymentProofPath != null &&
                              widget.sale.paymentProofPath!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildProofCard(),
                          ],
                          const SizedBox(height: 24),
                          _buildActions(canVerify, canViewEvidence),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              'Thank you for your purchase!',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildStoreHeader() {
    final store = _storeInfo;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store?.storeName ?? 'Pinoy POS',
            style: AppTypography.titleMediumBold(context),
          ),
          const SizedBox(height: 4),
          Text(
            'Receipt #${widget.sale.receiptNumber ?? widget.sale.id}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            widget.sale.createdAt.toLocal().toString().split('.')[0],
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool canVerify) {
    final cs = Theme.of(context).colorScheme;
    final status = widget.sale.paymentStatus;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'confirmed':
        statusColor = cs.primary;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusColor = cs.tertiary;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'cancelled':
      case 'refunded':
        statusColor = cs.error;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = cs.outline;
        statusIcon = Icons.help;
    }

    return AppCard(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Text(
                  'Status: ${status[0].toUpperCase()}${status.substring(1)}',
                  style: AppTypography.titleSmallBold(context)
                      .copyWith(color: statusColor),
                ),
              ],
            ),
            if (widget.sale.verifiedAt != null &&
                widget.sale.verifiedBy != null) ...[
              const SizedBox(height: 8),
              Text(
                'Verified at ${widget.sale.verifiedAt!.toLocal().toString().split('.')[0]}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (status == 'pending' && canVerify) ...[
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

  Widget _buildItemsCard() {
    return AppCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Item', style: Theme.of(context).textTheme.titleSmall),
              Text('Qty • Price • Total',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const Divider(),
          ..._items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _productNames[item.productId] ??
                            'Product #${item.productId}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${item.quantity} • ₱${item.unitPrice.toStringAsFixed(2)} • ₱${item.totalPrice.toStringAsFixed(2)}',
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    return AppCard(
      child: Column(
        children: [
          _buildRow('Subtotal',
              '₱${widget.sale.totalAmount.toStringAsFixed(2)}'),
          const Divider(),
          _buildRow('Cash Received',
              '₱${widget.sale.cashReceived.toStringAsFixed(2)}'),
          const Divider(),
          _buildRow('Change', '₱${widget.sale.change.toStringAsFixed(2)}'),
          const Divider(),
          _buildRow(
            'Total',
            '₱${widget.sale.totalAmount.toStringAsFixed(2)}',
            isTotal: true,
          ),
          const Divider(),
          _buildRow('Payment Method', widget.sale.paymentMethod),
          if (widget.sale.referenceNumber != null &&
              widget.sale.referenceNumber!.isNotEmpty)
            _buildRow('Reference', widget.sale.referenceNumber!),
          if (widget.sale.customerName != null &&
              widget.sale.customerName!.isNotEmpty)
            _buildRow('Customer', widget.sale.customerName!),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(widget.sale.notes!),
        ],
      ),
    );
  }

  Widget _buildProofCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Proof',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          FutureBuilder<File?>(
            future: ImageService().resolveImageFile(widget.sale.paymentProofPath),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final file = snapshot.data;
              if (file == null) {
                return const Text('Unable to load payment proof.');
              }
              return GestureDetector(
                onTap: _viewProof,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActions(bool canVerify, bool canViewEvidence) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _viewReceipt,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View Receipt'),
        ),
        if (canViewEvidence &&
            widget.sale.paymentProofPath != null &&
            widget.sale.paymentProofPath!.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _viewProof,
            icon: const Icon(Icons.image_outlined),
            label: const Text('View Payment Proof'),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? AppTypography.titleMediumBold(context)
                : Theme.of(context).textTheme.bodyMedium,
          ),
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
}
