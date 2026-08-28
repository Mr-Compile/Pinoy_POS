import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/screens/payment_proof_viewer_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final Sale sale;
  final List<SaleItem>? items;
  final Map<int, String>? productNames;

  const ReceiptScreen({
    super.key,
    required this.sale,
    this.items,
    this.productNames,
  });

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  List<SaleItem> _items = [];
  Map<int, String> _productNames = {};
  Settings? _storeInfo;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final salesService = ref.read(salesServiceProvider);
      final productService = ref.read(productServiceProvider);
      final reportService = ref.read(reportServiceProvider);

      final items = widget.items ?? await salesService.getSaleItems(widget.sale.id!);
      final names = <int, String>{};
      for (final item in items) {
        if (names.containsKey(item.productId)) continue;
        final product = await productService.getProductById(item.productId);
        names[item.productId] = product?.name ?? 'Product #${item.productId}';
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
        });
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to load receipt details.',
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (_storeInfo == null) return;

    setState(() => _isExporting = true);

    try {
      final receiptService = ref.read(receiptServiceProvider);
      final bytes = await receiptService.generateReceiptPdf(
        widget.sale,
        _items,
        _productNames,
        _storeInfo!,
      );

      final fileName = 'receipt_${widget.sale.receiptNumber ?? widget.sale.id}.pdf';
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
            message: 'The receipt was saved successfully.',
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

  Future<void> _viewPaymentProof() async {
    if (widget.sale.paymentProofPath == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentProofViewerScreen(sale: widget.sale),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        title: 'Receipt',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStoreHeader(),
                  const SizedBox(height: 16),
                  _buildItemsCard(),
                  const SizedBox(height: 16),
                  _buildPaymentCard(),
                  if (widget.sale.notes != null && widget.sale.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildNotesCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
    );
  }

  Widget _buildStoreHeader() {
    final store = _storeInfo;
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              store?.storeName ?? 'Pinoy POS',
              style: AppTypography.titleMediumBold(context)
                  .copyWith(color: cs.onPrimaryContainer),
              textAlign: TextAlign.center,
            ),
            if (store?.storeAddress.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                store!.storeAddress,
                style: TextStyle(color: cs.onPrimaryContainer),
                textAlign: TextAlign.center,
              ),
            ],
            if (store?.storePhone.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(
                'Contact: ${store!.storePhone}',
                style: TextStyle(color: cs.onPrimaryContainer),
                textAlign: TextAlign.center,
              ),
            ],
            const Divider(height: 24),
            Text(
              'Receipt #${widget.sale.receiptNumber ?? widget.sale.id}',
              style: AppTypography.titleSmallBold(context)
                  .copyWith(color: cs.onPrimaryContainer),
            ),
            Text(
              widget.sale.createdAt.toLocal().toString().split('.')[0],
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
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
          if (widget.sale.paymentMethod == 'Cash') ...[
            _buildRow('Cash Received',
                '₱${widget.sale.cashReceived.toStringAsFixed(2)}'),
            _buildRow('Change', '₱${widget.sale.change.toStringAsFixed(2)}'),
            const Divider(),
          ],
          _buildRow('Total',
              '₱${widget.sale.totalAmount.toStringAsFixed(2)}',
              isTotal: true),
          const Divider(),
          _buildRow('Payment Method', widget.sale.paymentMethod),
          if (widget.sale.referenceNumber != null &&
              widget.sale.referenceNumber!.isNotEmpty)
            _buildRow('Reference', widget.sale.referenceNumber!),
          if (widget.sale.customerName != null &&
              widget.sale.customerName!.isNotEmpty)
            _buildRow('Customer', widget.sale.customerName!),
          _buildRow(
            'Status',
            widget.sale.paymentStatus[0].toUpperCase() +
                widget.sale.paymentStatus.substring(1),
          ),
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

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.sale.paymentProofPath != null &&
            widget.sale.paymentProofPath!.isNotEmpty) ...[
          FutureBuilder<File?>(
            future: ImageService().resolveImageFile(widget.sale.paymentProofPath),
            builder: (context, snapshot) {
              final hasFile = snapshot.data != null;
              return OutlinedButton.icon(
                onPressed: hasFile ? _viewPaymentProof : null,
                icon: const Icon(Icons.image_outlined),
                label: const Text('View Payment Proof'),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        LoadingButton(
          isLoading: _isExporting,
          onPressed: _downloadPdf,
          label: 'Download as PDF',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: null, // Print not supported without printing package.
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print (unavailable)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: null, // Share not supported without share_plus package.
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share (unavailable)'),
        ),
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
