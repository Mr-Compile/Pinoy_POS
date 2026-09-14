import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Presents the unlock-code entry form anywhere outside the lock screen —
/// the expiry warning banner and the login screen link both use it so a
/// code can be redeemed BEFORE the license locks.
///
/// Returns the [LicenseRedeemResult] on success, `null` when cancelled.
/// Errors (invalid code, rate-limit lockout) are shown inline in the
/// dialog; the caller is responsible for the success feedback and for
/// refreshing `licenseStatusProvider`.
Future<LicenseRedeemResult?> showLicenseUnlockDialog(
  BuildContext context,
  LicenseService service,
) async {
  final result = await showDialog<ModalResult<LicenseRedeemResult>>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => AppDialogForm<ModalResult<LicenseRedeemResult>>(
      type: AppDialogType.edit,
      title: 'Enter Unlock Code',
      message:
          'Enter the code provided by the developer to extend the license.',
      showClose: false,
      childBuilder: (context, state) => Form(
        key: state.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextFormField(
              controller: state.textController('code'),
              label: 'Unlock code',
              hint: 'XXXX-XXXX',
              prefixIcon: Icons.key_outlined,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z-]')),
              ],
              textInputAction: TextInputAction.done,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter the unlock code'
                  : null,
              onChanged: (_) {
                state.markChanged();
                if (state.value<String>('error') != null) {
                  state.setValue<String>('error', null);
                }
              },
            ),
            if (state.value<String>('error') != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                state.value<String>('error')!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall(context).copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          onPressed: state.isSaving
              ? null
              : (context) => state.pop(
                  const ModalResult<LicenseRedeemResult>.cancelled(),
                ),
        ),
        AppDialogAction(
          label: 'Unlock',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving
              ? null
              : (context) async {
                  if (!state.formKey.currentState!.validate()) return;
                  state.setSaving(true);

                  final redeem = await service.redeemUnlockCode(
                    state.textController('code').text,
                  );
                  if (redeem.success) {
                    state.pop(ModalResult<LicenseRedeemResult>.saved(redeem));
                    return;
                  }
                  state.setSaving(false);
                  if (redeem.retryAfter != null) {
                    final minutes = redeem.retryAfter!.inMinutes + 1;
                    state.setValue<String>(
                      'error',
                      'Too many attempts. Try again in $minutes min.',
                    );
                  } else if (redeem.alreadyUsed) {
                    state.setValue<String>(
                      'error',
                      'This code has already been used on this device.',
                    );
                  } else {
                    state.setValue<String>(
                      'error',
                      'The unlock code is not valid.',
                    );
                  }
                },
        ),
      ],
    ),
  );

  if (result?.isSaved ?? false) return result!.value;
  return null;
}
