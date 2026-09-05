import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
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
    final settingsAsync = ref.watch(settingsProvider);
    final canEditTimeout =
        SessionManager().hasPermission('edit_settings');

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
            const SizedBox(height: 16),
            Text('Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'How long the app waits for input before locking the screen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Inactivity timeout'),
                subtitle: settingsAsync.when(
                  data: (settings) => Text(
                    '${settings.inactivityTimeoutMinutes} minutes',
                  ),
                  loading: () => const Text('Loading…'),
                  error: (_, _) => const Text('Unable to load'),
                ),
                trailing: canEditTimeout
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: canEditTimeout
                    ? () => _showInactivityTimeoutDialog(context, ref, settingsAsync)
                    : null,
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
          final strengthResult = PasswordStrengthService.evaluate(
            password: newController.text,
            username: user.username,
          );

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppPasswordField(
                  controller: oldController,
                  label: 'Current Password',
                  prefixIcon: Icons.lock_outline,
                  validator: (value) =>
                      Validators.required(value, 'Current password'),
                ),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: newController,
                  label: 'New Password',
                  prefixIcon: Icons.lock_outline,
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
                AppPasswordField(
                  controller: confirmController,
                  label: 'Confirm New Password',
                  prefixIcon: Icons.lock_outline,
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

  Future<void> _showInactivityTimeoutDialog(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Settings> settingsAsync,
  ) async {
    final current = settingsAsync.valueOrNull?.inactivityTimeoutMinutes ?? 15;
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: 'Inactivity Timeout',
        childBuilder: (context, state) {
          final minutesController = state.textController(
            'minutes',
            text: current.toString(),
          );

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Minutes of inactivity before the app locks. '
                  'This is the store default; a per-user override can be set in User Management.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: minutesController,
                  label: 'Minutes',
                  hint: 'e.g. 15',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Minutes is required';
                    }
                    final minutes = int.tryParse(value.trim());
                    if (minutes == null || minutes < 1 || minutes > 480) {
                      return 'Enter a number between 1 and 480';
                    }
                    return null;
                  },
                  onChanged: (_) => state.markChanged(),
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
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: (dialogContext) async {
              if (!state.formKey.currentState!.validate()) return;

              state.setSaving(true);

              final minutes =
                  int.parse(state.textController('minutes').text.trim());
              final settings = settingsAsync.valueOrNull;
              if (settings == null) {
                state.setSaving(false);
                return;
              }

              final updated = await ref
                  .read(settingsServiceProvider)
                  .updateSettings(
                    settings.copyWith(inactivityTimeoutMinutes: minutes),
                  );

              if (updated) {
                ref.invalidate(settingsProvider);
                state.pop(const ModalResult<void>.saved());
              } else {
                if (dialogContext.mounted) {
                  state.setSaving(false);
                  await AppDialogService.error(
                    dialogContext,
                    title: 'Save Failed',
                    message: 'Unable to save the inactivity timeout.',
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
        title: 'Updated',
        message: 'Inactivity timeout updated.',
      );
    }
  }
}
