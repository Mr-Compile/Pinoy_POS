import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Full-screen payment evidence viewer. Requires `view_payment_evidence`.
class PaymentProofViewerScreen extends ConsumerStatefulWidget {
  final Sale sale;

  const PaymentProofViewerScreen({super.key, required this.sale});

  @override
  ConsumerState<PaymentProofViewerScreen> createState() =>
      _PaymentProofViewerScreenState();
}

class _PaymentProofViewerScreenState
    extends ConsumerState<PaymentProofViewerScreen> {
  File? _file;
  bool _isLoading = true;
  bool _isReplacing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
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

      final file =
          await ImageService().resolveImageFile(widget.sale.paymentProofPath);
      if (mounted) {
        setState(() {
          _file = file;
          _isLoading = false;
          _error = file == null ? 'Payment proof not found.' : null;
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

  Future<void> _replaceProof() async {
    final canVerify = ref
        .read(authStateProvider.notifier)
        .hasPermission('verify_payments');
    final isOwn = ref.read(authStateProvider).user?.id == widget.sale.userId;

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
        widget.sale.id!,
        result.filePath!,
      );

      if (mounted) {
        setState(() => _isReplacing = false);
        if (newPath != null) {
          await AppDialogService.success(
            context,
            title: 'Proof Replaced',
            message: 'Payment evidence updated successfully.',
          );
          await _loadFile();
        } else {
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
    final isOwn = ref.read(authStateProvider).user?.id == widget.sale.userId;

    return Scaffold(
      appBar: AppHeader(
        title: 'Payment Proof',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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

    if (_file == null) {
      return const Center(child: Text('Payment proof not found.'));
    }

    return Stack(
      children: [
        InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(
            child: Image.file(
              _file!,
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (_isReplacing)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

}
