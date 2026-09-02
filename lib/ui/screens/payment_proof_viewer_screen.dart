import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/payment_proof_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Full-screen GCash payment evidence viewer. Requires `view_payment_evidence`.
///
/// GCash payment proofs are always images. The viewer shows the detected
/// file type and provides Refresh, Download Image, and Replace actions.
class PaymentProofViewerScreen extends ConsumerStatefulWidget {
  final Sale sale;

  const PaymentProofViewerScreen({super.key, required this.sale});

  @override
  ConsumerState<PaymentProofViewerScreen> createState() =>
      _PaymentProofViewerScreenState();
}

class _PaymentProofViewerScreenState
    extends ConsumerState<PaymentProofViewerScreen> {
  late Sale _sale;
  PaymentProofInfo? _info;
  bool _isLoading = true;
  bool _isReplacing = false;
  bool _isExporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
    _loadFile();
  }

  Future<void> _loadFile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final canView = ref
          .read(authStateProvider.notifier)
          .hasPermission('view_payment_evidence');
      if (!canView) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'You do not have permission to view payment evidence.';
          });
        }
        return;
      }

      final paymentProofService = ref.read(paymentProofServiceProvider);
      final info = await paymentProofService.resolveProof(_sale);

      if (mounted) {
        setState(() {
          _info = info;
          _isLoading = false;
          if (info == null) {
            _error = 'No payment proof is available for this transaction.';
          } else if (info.fileType == null) {
            _error = 'Unable to determine the proof image type.';
          } else if (!info.isImage) {
            _error = 'Unable to open the payment proof. The file is not a supported image.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Unable to load payment proof.';
        });
      }
    }
  }

  Future<void> _downloadImage() async {
    if (_info == null) return;

    setState(() => _isExporting = true);

    try {
      final paymentProofService = ref.read(paymentProofServiceProvider);
      final saved = await paymentProofService.exportGcashProofAsImage(_sale);

      if (!mounted) return;

      setState(() => _isExporting = false);

      if (saved == null) {
        // User cancelled or save failed silently.
        return;
      }

      await AppDialogService.success(
        context,
        title: 'Image Saved',
        message: 'GCash proof image saved to $saved.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        AppDialogService.error(
          context,
          title: 'Download Failed',
          message: 'Unable to save the GCash proof image: $e',
        );
      }
    }
  }

  Future<void> _replaceProof() async {
    final canVerify = ref
        .read(authStateProvider.notifier)
        .hasPermission('verify_payments');
    final isOwn = ref.read(authStateProvider).user?.id == _sale.userId;

    if (!canVerify && !isOwn) {
      AppDialogService.accessDenied(context);
      return;
    }

    setState(() => _isReplacing = true);

    try {
      final result = await ImageService().pickAndStoreImage(
        source: ImageSource.camera,
        directory: 'payment_evidence/tmp',
      );

      if (!mounted) return;

      if (!result.isSuccess || result.filePath == null) {
        setState(() => _isReplacing = false);
        if (result.error != null) {
          AppDialogService.error(
            context,
            title: 'Unable to replace proof',
            message: result.error!,
          );
        }
        return;
      }

      final salesService = ref.read(salesServiceProvider);
      final newPath = await salesService.replacePaymentProof(
        _sale.id!,
        result.filePath!,
      );

      if (mounted) {
        if (newPath != null) {
          _sale = _sale.copyWith(
            paymentProofPath: newPath,
            paymentProofType: result.mediaType,
          );
          await AppDialogService.success(
            context,
            title: 'Proof Replaced',
            message: 'Payment evidence updated successfully.',
          );
          await _loadFile();
        } else {
          setState(() => _isReplacing = false);
          AppDialogService.error(
            context,
            title: 'Replace Failed',
            message: 'Unable to replace payment proof.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isReplacing = false);
        AppDialogService.error(
          context,
          title: 'Replace Failed',
          message: 'An error occurred while replacing the proof.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canVerify = ref
        .read(authStateProvider.notifier)
        .hasPermission('verify_payments');
    final isOwn = ref.read(authStateProvider).user?.id == _sale.userId;

    return Scaffold(
      appBar: AppHeader(
        title: 'Payment Proof',
        showBackButton: true,
        actions: [
          if (_info != null && _info!.isImage)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download Image',
              onPressed: _isExporting ? null : _downloadImage,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadFile,
          ),
        ],
      ),
      floatingActionButton: (canVerify || isOwn) && !_isLoading && _error == null
          ? FloatingActionButton.extended(
              onPressed: _isReplacing ? null : _replaceProof,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Replace'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingState();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final info = _info;
    if (info == null) {
      return const Center(child: Text('Payment proof not found.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildPreview(info),
        ),
        _buildMetadata(info),
      ],
    );
  }

  Widget _buildPreview(PaymentProofInfo info) {
    final cs = Theme.of(context).colorScheme;

    if (info.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.file(
            info.file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 64, color: cs.outline),
                      const SizedBox(height: 16),
                      Text(
                        'Unable to display this image.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              'Unable to open the payment proof.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadata(PaymentProofInfo info) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeLabel = info.fileType?.label ?? 'Image';
    final size = _formatFileSize(info.sizeBytes);
    final name = info.originalName ?? 'Unknown file';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$typeLabel • $size',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isExporting ? null : _downloadImage,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('Download Image'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
