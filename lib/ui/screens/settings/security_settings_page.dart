import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/password_strength_meter.dart';

/// Security settings sub-page — change password.
///
/// Accessible from the Settings hub. Available to all authenticated
/// users (users can always change their own password).
class SecuritySettingsPage extends ConsumerWidget {
  const SecuritySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (user == null) {
      return Scaffold(
        appBar: const AppHeader(title: 'Security', showBackButton: true),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Security', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Password', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Change your account password. You will need to enter your current password.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change Password'),
                subtitle: const Text('Update your login password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePasswordDialog(context, ref, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: 'Change Password',
        childBuilder: (context, state) {
          final oldController = state.textController('oldPassword');
          final newController = state.textController('newPassword');
          final confirmController = state.textController('confirmPassword');
          final obscureOld =
              state.value<bool>('obscureOldPassword', true) ?? true;
          final obscureNew =
              state.value<bool>('obscureNewPassword', true) ?? true;
          final obscureConfirm =
              state.value<bool>('obscureConfirmPassword', true) ?? true;
          final strengthResult = PasswordStrengthService.evaluate(
            password: newController.text,
            username: user.username,
          );

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldController,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureOld
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => state.setValue<bool>(
                        'obscureOldPassword',
                        !obscureOld,
                      ),
                      tooltip: obscureOld ? 'Show password' : 'Hide password',
                    ),
                  ),
                  obscureText: obscureOld,
                  validator: (value) =>
                      Validators.required(value, 'Current password'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => state.setValue<bool>(
                        'obscureNewPassword',
                        !obscureNew,
                      ),
                      tooltip: obscureNew ? 'Show password' : 'Hide password',
                    ),
                  ),
                  obscureText: obscureNew,
                  onChanged: (value) {
                    state.markChanged();
                    state.setValue<bool>('newPasswordTouched', true);
                  },
                  validator: (value) {
                    if (!(state.value<bool>('newPasswordTouched', false) ??
                        false)) {
                      return null;
                    }
                    if (value == null || value.isEmpty) {
                      return 'Enter a new password.';
                    }
                    return PasswordStrengthService.validate(
                      password: value,
                      username: user.username,
                      currentPassword: oldController.text,
                    );
                  },
                ),
                if (newController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PasswordStrengthMeter(result: strengthResult),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => state.setValue<bool>(
                        'obscureConfirmPassword',
                        !obscureConfirm,
                      ),
                      tooltip:
                          obscureConfirm ? 'Show password' : 'Hide password',
                    ),
                  ),
                  obscureText: obscureConfirm,
                  onChanged: (value) {
                    state.setValue<bool>('confirmPasswordTouched', true);
                  },
                  validator: (value) {
                    if (!(state.value<bool>('confirmPasswordTouched', false) ??
                        false)) {
                      return null;
                    }
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password.';
                    }
                    if (value != newController.text) {
                      return 'Your passwords don\'t match.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (dialogContext) =>
                state.pop(const ModalResult<void>.cancelled()),
          ),
          AppDialogAction(
            label: 'Change',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: (dialogContext) async {
              state.setValue<bool>('newPasswordTouched', true);
              state.setValue<bool>('confirmPasswordTouched', true);

              if (!state.formKey.currentState!.validate()) return;

              state.setSaving(true);

              final result = await ref
                  .read(userControllerProvider.notifier)
                  .changePassword(
                    userId: user.id!,
                    oldPassword: state.textController('oldPassword').text,
                    newPassword: state.textController('newPassword').text,
                  );

              if (result.success) {
                state.pop(const ModalResult<void>.saved());
              } else {
                if (dialogContext.mounted) {
                  state.setSaving(false);
                  await AppDialogService.error(
                    dialogContext,
                    title: 'Change Failed',
                    message: result.message,
                  );
                }
              }
            },
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (result?.isSaved ?? false) {
      await AppDialogService.success(
        context,
        title: 'Password Changed',
        message: 'Your password has been changed successfully.',
      );
    }
  }
}
