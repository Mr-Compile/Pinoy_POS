import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/payment_proof_provider.dart';
import 'package:pinoy_pos/providers/receipt_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';
import 'package:pinoy_pos/ui/screens/payment_proof_viewer_screen.dart';
import 'package:pinoy_pos/ui/screens/receipt_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  final Sale? sale;
  final int? saleId;

  const SaleDetailScreen({super.key, this.sale, this.saleId})
    : assert(sale != null || saleId != null);

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _isProcessing = false;
  bool _isExporting = false;
  bool _isPrinting = false;
  bool _isLoading = false;
  bool _notFound = false;
  Sale? _loadedSale;
  final Map<String, Future<PaymentProofInfo?>> _proofFutures = {};
  final Map<int, Future<Product?>> _productFutures = {};

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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReceiptScreen(sale: _sale)));
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

  Future<void> _printReceipt(ReceiptViewData receipt) async {
    setState(() => _isPrinting = true);
    try {
      final receiptService = ref.read(receiptServiceProvider);
      final bytes = await receiptService.generateReceiptPdf(receipt);
      final fileName = receiptService.buildFileName(receipt);

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fileName,
      );
    } catch (e) {
      if (mounted) {
        AppDialogService.error(
          context,
          title: 'Print Failed',
          message: 'Unable to print the receipt: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _downloadGcashProofImage() async {
    try {
      final paymentProofService = ref.read(paymentProofServiceProvider);
      final saved = await paymentProofService.exportGcashProofAsImage(_sale);

      if (mounted) {
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
        AppDialogService.error(
          context,
          title: 'Download Failed',
          message: 'Unable to save the GCash proof image: $e',
        );
      }
    }
  }

  Future<void> _viewPaymentProof() async {
    if (_sale.paymentProofPath == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentProofViewerScreen(sale: _sale)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Sale Details', showBackButton: true),
        body: LoadingState(),
      );
    }

    if (_notFound || _saleId <= 0) {
      return Scaffold(
        appBar: const AppHeader(title: 'Sale Not Found', showBackButton: true),
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
    final canViewEvidence = authNotifier.hasPermission('view_payment_evidence');

    return receiptAsync.when(
      loading: () => const Scaffold(
        appBar: AppHeader(title: 'Sale Details', showBackButton: true),
        body: LoadingState(),
      ),
      error: (e, _) => Scaffold(
        appBar: const AppHeader(title: 'Sale Details', showBackButton: true),
        body: ErrorState(
          title: 'Error',
          message: 'Failed to load sale details: $e',
          onRetry: () => ref.invalidate(receiptViewDataProvider(_saleId)),
        ),
      ),
      data: (receipt) {
        if (receipt == null) {
          return const Scaffold(
            appBar: AppHeader(title: 'Sale Details', showBackButton: true),
            body: ErrorState(
              title: 'Not Found',
              message:
                  'The sale could not be found or you do not have permission to view it.',
            ),
          );
        }
        return _buildScaffold(receipt, canVerify, canViewEvidence);
      },
    );
  }

  Widget _buildScaffold(
    ReceiptViewData receipt,
    bool canVerify,
    bool canViewEvidence,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sale #${receipt.receiptNumber}',
              style: AppTypography.titleMediumBold(context),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              _formatHeaderDate(receipt.date),
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
        actions: isCompact
            ? [
                _buildPrintAction(receipt),
                _buildMoreAction(
                  receipt,
                  canViewEvidence,
                  includePrint: true,
                  includeDownloadPdf: true,
                ),
              ]
            : [
                _buildPrintAction(receipt),
                _buildDownloadAction(receipt),
                _buildMoreAction(
                  receipt,
                  canViewEvidence,
                  includePrint: false,
                  includeDownloadPdf: false,
                ),
              ],
      ),
      body: _buildBody(receipt, canVerify, canViewEvidence),
    );
  }

  Widget _buildPrintAction(ReceiptViewData receipt) {
    return IconButton(
      icon: _isPrinting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.print_outlined),
      tooltip: 'Print',
      onPressed: _isPrinting ? null : () => _printReceipt(receipt),
    );
  }

  Widget _buildDownloadAction(ReceiptViewData receipt) {
    return IconButton(
      icon: _isExporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      tooltip: 'Download PDF',
      onPressed: _isExporting ? null : () => _downloadPdf(receipt),
    );
  }

  Widget _buildMoreAction(
    ReceiptViewData receipt,
    bool canViewEvidence, {
    bool includePrint = false,
    bool includeDownloadPdf = false,
  }) {
    final hasProof = canViewEvidence &&
        receipt.paymentProofPath != null &&
        receipt.paymentProofPath!.isNotEmpty;

    if (!includePrint && !includeDownloadPdf && !hasProof) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More',
      onSelected: (value) => _handleMoreAction(value, receipt),
      itemBuilder: (context) => [
        if (includePrint)
          const PopupMenuItem(
            value: 'print',
            child: _MenuRow(icon: Icons.print, label: 'Print'),
          ),
        if (includeDownloadPdf)
          const PopupMenuItem(
            value: 'download_pdf',
            child: _MenuRow(icon: Icons.download, label: 'Download PDF'),
          ),
        if (hasProof) ...[
          const PopupMenuItem(
            value: 'view_image',
            child: _MenuRow(icon: Icons.image_outlined, label: 'View Image'),
          ),
          const PopupMenuItem(
            value: 'download_image',
            child: _MenuRow(
              icon: Icons.save_alt,
              label: 'Download Image',
            ),
          ),
        ],
      ],
    );
  }

  void _handleMoreAction(String value, ReceiptViewData receipt) {
    switch (value) {
      case 'print':
        _printReceipt(receipt);
        break;
      case 'download_pdf':
        _downloadPdf(receipt);
        break;
      case 'view_image':
        _viewPaymentProof();
        break;
      case 'download_image':
        _downloadGcashProofImage();
        break;
    }
  }

  Widget _buildBody(
    ReceiptViewData receipt,
    bool canVerify,
    bool canViewEvidence,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);

        // Main content column shared across breakpoints.
        final statusBanner = _buildStatusBanner(receipt, canVerify);
        final overviewCard = _buildOverviewCard(receipt);
        final totalCard = _buildTotalCard(receipt);
        final itemsCard = _buildItemsCard(receipt);
        final paymentCard = _buildPaymentCard(receipt, canVerify);
        final receiptPreview = canViewEvidence &&
                receipt.paymentProofPath != null &&
                receipt.paymentProofPath!.isNotEmpty
            ? _buildReceiptPreviewCard(receipt)
            : null;
        final notesCard = receipt.notes != null && receipt.notes!.isNotEmpty
            ? _buildNotesCard(receipt)
            : null;
        final bottomActions = _buildBottomActions(receipt);

        if (layout == LayoutClass.compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _punctuate([
                    statusBanner,
                    overviewCard,
                    totalCard,
                    itemsCard,
                    paymentCard,
                    receiptPreview,
                    notesCard,
                    bottomActions,
                  ]),
                ),
              ),
            ),
          );
        }

        // Medium / expanded: multi-column dashboard layout.
        final topRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _expandRow([
            overviewCard,
            const SizedBox(width: Spacing.lg),
            totalCard,
          ]),
        );

        final bottomRowChildren = [paymentCard];
        if (receiptPreview != null) {
          bottomRowChildren.add(const SizedBox(width: Spacing.lg));
          bottomRowChildren.add(receiptPreview);
        }
        final bottomRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _expandRow(bottomRowChildren),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _punctuate([
                  statusBanner,
                  topRow,
                  itemsCard,
                  bottomRow,
                  notesCard,
                  bottomActions,
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _punctuate(List<Widget?> children) {
    final result = <Widget>[];
    for (final child in children) {
      if (child == null) continue;
      if (result.isNotEmpty) result.add(const SizedBox(height: Spacing.md));
      result.add(child);
    }
    return result;
  }

  List<Widget> _expandRow(List<Widget> children) {
    return children
        .map(
          (child) =>
              child is SizedBox ? child : Expanded(child: child),
        )
        .toList();
  }

  // ── Status banner ───────────────────────────────────────────────

  Widget _buildStatusBanner(ReceiptViewData receipt, bool canVerify) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(receipt.paymentStatus, cs);
    final statusIcon = _statusIcon(receipt.paymentStatus);

    final (title, subtitle) = switch (receipt.paymentStatus) {
      'confirmed' => ('Completed', 'Payment received successfully'),
      'pending' => ('Pending', 'Awaiting payment confirmation'),
      'cancelled' => ('Cancelled', 'Payment was cancelled'),
      'refunded' => ('Refunded', 'Payment was refunded'),
      _ => (receipt.statusLabel, 'Payment status: ${receipt.statusLabel}'),
    };

    return AppCard(
      padding: EdgeInsets.zero,
      color: statusColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(statusIcon, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTypography.titleMediumBold(context).copyWith(
                          color: statusColor,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall(context).copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyUtils.format(receipt.total, currency: receipt.currency),
                  style: AppTypography.headlineSmallSemibold(context).copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            if (receipt.paymentStatus == 'pending' && canVerify) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton.filled(
                      label: 'Confirm',
                      color: AppButtonColor.success,
                      isLoading: _isProcessing,
                      onPressed: _confirmPayment,
                      fullWidth: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.filled(
                      label: 'Reject',
                      color: AppButtonColor.error,
                      isLoading: _isProcessing,
                      onPressed: _rejectPayment,
                      fullWidth: true,
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

  // ── Transaction overview ────────────────────────────────────────

  Widget _buildOverviewCard(ReceiptViewData receipt) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: ResponsiveBuilder(
          builder: (context, layout) {
            final tiles = [
              _buildOverviewTile(
                icon: Icons.receipt_long_outlined,
                label: 'Receipt Number',
                value: receipt.receiptNumber,
              ),
              _buildOverviewTile(
                icon: Icons.calendar_today_outlined,
                label: 'Date & Time',
                value: '${_formatDate(receipt.date)}\n${_formatTime(receipt.date)}',
              ),
              _buildOverviewTile(
                icon: Icons.person_outline,
                label: 'Customer',
                value: receipt.customerName?.isNotEmpty == true
                    ? receipt.customerName!
                    : 'Walk-in Customer',
              ),
              _buildOverviewTile(
                icon: Icons.badge_outlined,
                label: 'Cashier',
                value: receipt.cashierName,
              ),
            ];

            return switch (layout) {
              LayoutClass.compact => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _punctuate(tiles),
                ),
              LayoutClass.medium => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _expandRow([
                        tiles[0],
                        const SizedBox(width: Spacing.md),
                        tiles[1],
                      ]),
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _expandRow([
                        tiles[2],
                        const SizedBox(width: Spacing.md),
                        tiles[3],
                      ]),
                    ),
                  ],
                ),
              LayoutClass.expanded => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _expandRow(
                    _intersperse(tiles, const SizedBox(width: Spacing.md)),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }

  Widget _buildOverviewTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.bodyMediumSemibold(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Financial summary ───────────────────────────────────────────

  Widget _buildTotalCard(ReceiptViewData receipt) {
    final cs = Theme.of(context).colorScheme;
    final tax = receipt.total - receipt.subtotal - receipt.discount;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.primary, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total Amount',
                  style: AppTypography.labelSmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyUtils.format(
                    receipt.total,
                    currency: receipt.currency,
                  ),
                  style: AppTypography.headlineSmallBold(context).copyWith(
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMoneyRow('Subtotal', receipt.subtotal, receipt.currency),
                _buildMoneyRow('Discount', receipt.discount, receipt.currency),
                if (tax > 0) _buildMoneyRow('Tax', tax, receipt.currency),
                if (receipt.cashReceived > 0) ...[
                  _buildMoneyRow(
                    'Amount Paid',
                    receipt.cashReceived,
                    receipt.currency,
                  ),
                  _buildMoneyRow(
                    'Change',
                    receipt.change,
                    receipt.currency,
                  ),
                ],
                const Divider(height: 24),
                _buildMoneyRow(
                  'Total',
                  receipt.total,
                  receipt.currency,
                  isTotal: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoneyRow(
    String label,
    double amount,
    String currency, {
    bool isTotal = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: isTotal
                  ? AppTypography.bodyMedium(context).copyWith(
                      fontWeight: FontWeight.bold,
                    )
                  : AppTypography.bodyMedium(context),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            CurrencyUtils.format(amount, currency: currency),
            style: isTotal
                ? AppTypography.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  )
                : AppTypography.bodyMedium(context),
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }

  // ── Items ───────────────────────────────────────────────────────

  Widget _buildItemsCard(ReceiptViewData receipt) {
    final cs = Theme.of(context).colorScheme;
    final count = receipt.items.length;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Items',
                    style: AppTypography.titleMediumBold(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count item${count == 1 ? '' : 's'}',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Product?>>(
              future: _productsFuture(receipt),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final products = snapshot.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < receipt.items.length; i++) ...[
                      _buildItemTile(
                        receipt.items[i],
                        i < products.length ? products[i] : null,
                        receipt.currency,
                      ),
                      if (i < receipt.items.length - 1)
                        const Divider(height: 16),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Product?>> _productsFuture(ReceiptViewData receipt) {
    return Future.wait(
      receipt.items.map((item) {
        return _productFutures.putIfAbsent(
          item.productId,
          () => ref.read(productServiceProvider).getProductById(item.productId),
        );
      }),
    );
  }

  Widget _buildItemTile(ReceiptItem item, Product? product, String currency) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 40,
              height: 40,
              child: AppImage(
                imagePath: product?.imageUrl,
                placeholderIcon: Icons.inventory_2,
                placeholderIconSize: 20,
                borderRadius: 0,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: AppTypography.bodyMediumSemibold(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${CurrencyUtils.format(item.unitPrice, currency: currency)} × ${item.quantity}',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              CurrencyUtils.format(item.totalPrice, currency: currency),
              style: AppTypography.bodyMedium(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment information ─────────────────────────────────────────

  Widget _buildPaymentCard(ReceiptViewData receipt, bool canVerify) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(receipt.paymentStatus, cs);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment Information',
                    style: AppTypography.titleMediumBold(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPaymentRow('Method', receipt.paymentMethod),
            if (receipt.referenceNumber?.isNotEmpty == true)
              _buildPaymentRow('Reference', receipt.referenceNumber!),
            if (receipt.customerName?.isNotEmpty == true)
              _buildPaymentRow('Customer', receipt.customerName!),
            _buildPaymentRowWidget(
              'Status',
              AppStatusChip(
                label: receipt.statusLabel,
                color: statusColor,
                icon: _statusIcon(receipt.paymentStatus),
                filled: true,
              ),
            ),
            if (receipt.paymentStatus == 'pending' && canVerify) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton.filled(
                      label: 'Confirm',
                      color: AppButtonColor.success,
                      isLoading: _isProcessing,
                      onPressed: _confirmPayment,
                      fullWidth: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.filled(
                      label: 'Reject',
                      color: AppButtonColor.error,
                      isLoading: _isProcessing,
                      onPressed: _rejectPayment,
                      fullWidth: true,
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

  Widget _buildPaymentRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMediumSemibold(context),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRowWidget(String label, Widget value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          value,
        ],
      ),
    );
  }

  // ── Receipt preview / payment proof ─────────────────────────────

  Widget _buildReceiptPreviewCard(ReceiptViewData receipt) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.file_present_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Receipt Preview',
                    style: AppTypography.titleMediumBold(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final info = snapshot.data;
                if (info == null || !info.isImage) {
                  return _buildProofEmptyState();
                }

                return GestureDetector(
                  onTap: _viewPaymentProof,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.file(
                          info.file,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildProofEmptyState();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.remove_red_eye_outlined,
                        size: 16,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tap to enlarge',
                        style: AppTypography.bodyMedium(context).copyWith(
                          color: cs.primary,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProofEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No payment proof available',
              style: AppTypography.bodyMedium(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Notes ───────────────────────────────────────────────────────

  Widget _buildNotesCard(ReceiptViewData receipt) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Notes', style: AppTypography.titleMediumBold(context)),
            const SizedBox(height: 8),
            Text(receipt.notes!, style: AppTypography.bodyMedium(context)),
          ],
        ),
      ),
    );
  }

  // ── Bottom actions ──────────────────────────────────────────────

  Widget _buildBottomActions(ReceiptViewData receipt) {
    return ResponsiveBuilder(
      builder: (context, layout) {
        final viewButton = AppButton.outlined(
          label: 'View Receipt',
          icon: Icons.receipt_long_outlined,
          color: AppButtonColor.primary,
          onPressed: _viewReceipt,
          fullWidth: layout.isCompact,
        );

        final downloadButton = AppButton.filled(
          label: 'Download PDF',
          icon: Icons.download,
          color: AppButtonColor.primary,
          isLoading: _isExporting,
          onPressed: _isExporting ? null : () => _downloadPdf(receipt),
          fullWidth: layout.isCompact,
        );

        if (layout.isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              viewButton,
              const SizedBox(height: 12),
              downloadButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: viewButton),
            const SizedBox(width: 12),
            Expanded(child: downloadButton),
          ],
        );
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String _formatHeaderDate(DateTime date) {
    return DateFormat('MMM d, y \u2022 hh:mm a').format(date.toLocal());
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y').format(date.toLocal());
  }

  String _formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date.toLocal());
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    if (items.isEmpty) return items;
    final result = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      result.add(separator);
      result.add(items[i]);
    }
    return result;
  }

  Color _statusColor(String status, ColorScheme cs) {
    final brightness = Theme.of(context).brightness;
    return switch (status) {
      'confirmed' =>
        AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      'pending' =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      'cancelled' || 'refunded' =>
        AppSemanticColors.resolve(AppSemanticColors.error, brightness),
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

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurface),
        const SizedBox(width: 12),
        Text(label, style: AppTypography.bodyMedium(context)),
      ],
    );
  }
}
