import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Shows the at-till GCash payment verification dialog.
///
/// Displayed when a Staff-tendered GCash payment requires approval under the
/// configured verification policy. An authorized verifier (Owner, or System
/// Admin when the policy allows) enters their own credentials to approve the
/// payment before the sale is created.
///
/// Returns:
/// - `ModalResult.saved(verifier)` when an authorized verifier approves.
/// - `ModalResult.cancelled()` / null when the operator cancels — callers
///   must then abort the sale without touching the cart.
Future<ModalResult<User>?> showGcashVerificationDialog(
  BuildContext context, {
  required double total,
  required String operatorName,
  required PaymentSettings settings,
}) {
  return showDialog<ModalResult<User>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _GcashVerificationDialog(
      total: total,
      operatorName: operatorName,
      settings: settings,
    ),
  );
}

class _GcashVerificationDialog extends ConsumerWidget {
  final double total;
  final String operatorName;
  final PaymentSettings settings;

  const _GcashVerificationDialog({
    required this.total,
    required this.operatorName,
    required this.settings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppDialogForm<ModalResult<User>>(
      type: AppDialogType.warning,
      title: 'GCash Payment Verification',
      message:
          'An authorized verifier must approve this payment before the sale is completed.',
      childBuilder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final error = state.value<String>('error');
        final usernameController = state.textController('username');
        final passwordController = state.textController('password');

        return Form(
          key: state.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                variant: AppCardVariant.filled,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _summaryRow(context, 'Amount',
                        CurrencyUtils.format(total)),
                    const SizedBox(height: 8),
                    _summaryRow(context, 'Operator', operatorName),
                    const SizedBox(height: 8),
                    _summaryRow(context, 'Payment Method', 'GCash'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (error != null && error.isNotEmpty) ...[
                Text(
                  error,
                  style: TextStyle(color: cs.error),
                ),
                const SizedBox(height: 12),
              ],
              AppTextFormField(
                controller: usernameController,
                label: 'Verifier Username',
                prefixIcon: Icons.badge_outlined,
                enabled: !state.isSaving,
                validator: (value) =>
                    Validators.required(value, 'Verifier username'),
                onChanged: (_) => state.markChanged(),
              ),
              const SizedBox(height: 12),
              AppPasswordField(
                controller: passwordController,
                label: 'Verifier Password',
                prefixIcon: Icons.lock_outline,
                enabled: !state.isSaving,
                isLoading: state.isSaving,
                validator: (value) =>
                    Validators.required(value, 'Verifier password'),
                onChanged: (_) => state.markChanged(),
                onFieldSubmitted: (_) => _verify(state, ref),
              ),
            ],
          ),
        );
      },
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          isLoading: state.isSaving,
          onPressed: state.isSaving
              ? null
              : (context) => state.pop(const ModalResult<User>.cancelled()),
        ),
        AppDialogAction(
          label: 'Verify & Approve',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving
              ? null
              : (context) => _verify(state, ref),
        ),
      ],
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: AppTypography.titleSmallBold(context),
        ),
      ],
    );
  }

  Future<void> _verify(
    AppDialogFormState<ModalResult<User>> state,
    WidgetRef ref,
  ) async {
    if (!state.formKey.currentState!.validate()) {
      return;
    }

    state.setSaving(true);
    try {
      final result = await ref
          .read(paymentVerificationServiceProvider)
          .authenticateVerifier(
            username: state.textController('username').text,
            password: state.textController('password').text,
            settings: settings,
          );

      if (!state.mounted) return;

      if (result.isSuccess) {
        state.pop(ModalResult<User>.saved(result.verifier));
      } else {
        state.setSaving(false);
        state.setValue<String>('error', result.error);
      }
    } catch (_) {
      if (state.mounted) {
        state.setSaving(false);
        state.setValue<String>(
          'error',
          'Verification failed. Please try again.',
        );
      }
    }
  }
}
