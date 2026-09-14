import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Presents the developer access gate for the hidden license panel.
///
/// - No password configured yet → first-time setup (create + confirm).
/// - Password configured → verification.
/// - Stored state untrusted → an error is shown and nothing is entered.
///
/// Returns `true` when the caller may open the developer panel.
Future<bool> showDeveloperAccessDialog(
  BuildContext context,
  LicenseService service,
) async {
  final mode = await service.developerGateMode();
  if (!context.mounted) return false;

  if (mode == DevGateMode.blocked) {
    await AppDialogService.error(
      context,
      title: 'Access Unavailable',
      message:
          'The license state could not be verified. Use an unlock code to '
          'restore access.',
    );
    return false;
  }

  final result = await showDialog<ModalResult<void>>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => AppDialogForm<ModalResult<void>>(
      type: AppDialogType.restriction,
      title: mode == DevGateMode.setup
          ? 'Create Developer Password'
          : 'Developer Access',
      message: mode == DevGateMode.setup
          ? 'Set the password that protects the license controls.'
          : 'Enter the developer password to continue.',
      showClose: false,
      childBuilder: (context, state) => Form(
        key: state.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mode == DevGateMode.setup) ...[
              AppPasswordField(
                controller: state.textController('new'),
                label: 'New password',
                hint: 'At least 6 characters',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
                onChanged: (_) => state.markChanged(),
              ),
              const SizedBox(height: Spacing.md),
              AppPasswordField(
                controller: state.textController('confirm'),
                label: 'Confirm password',
                hint: 'Repeat the password',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value != state.textController('new').text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
                onChanged: (_) => state.markChanged(),
              ),
            ] else
              AppPasswordField(
                controller: state.textController('password'),
                label: 'Password',
                hint: 'Developer password',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.done,
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Enter the password' : null,
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
              : (context) => state.pop(const ModalResult<void>.cancelled()),
        ),
        AppDialogAction(
          label: mode == DevGateMode.setup ? 'Create' : 'Unlock',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving
              ? null
              : (context) async {
                  if (!state.formKey.currentState!.validate()) return;
                  state.setSaving(true);

                  if (mode == DevGateMode.setup) {
                    final created = await service.initializeDeveloperPassword(
                      state.textController('new').text,
                    );
                    if (created) {
                      state.pop(const ModalResult<void>.saved(null));
                    } else {
                      state.setSaving(false);
                      state.setValue<String>(
                        'error',
                        'A developer password already exists.',
                      );
                    }
                    return;
                  }

                  final response = await service.verifyDeveloperPassword(
                    state.textController('password').text,
                  );
                  switch (response.result) {
                    case DevAuthResult.ok:
                      state.pop(const ModalResult<void>.saved(null));
                    case DevAuthResult.incorrect:
                      state.setSaving(false);
                      state.setValue<String>(
                        'error',
                        'Incorrect password.',
                      );
                    case DevAuthResult.lockedOut:
                      state.setSaving(false);
                      final minutes =
                          (response.retryAfter?.inMinutes ?? 0) + 1;
                      state.setValue<String>(
                        'error',
                        'Too many attempts. Try again in $minutes min.',
                      );
                    case DevAuthResult.notSet:
                    case DevAuthResult.denied:
                      state.setSaving(false);
                      state.setValue<String>(
                        'error',
                        'Developer access is not available.',
                      );
                  }
                },
        ),
      ],
    ),
  );

  return result?.isSaved ?? false;
}
