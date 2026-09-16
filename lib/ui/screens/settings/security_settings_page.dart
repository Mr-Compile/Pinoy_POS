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
import 'package:pinoy_pos/services/session_settings_service.dart';
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
///
/// Session management (inactivity timeout and warning) is only visible
/// and editable by users with the `manage_session_settings` permission
/// (System Admin).
class SecuritySettingsPage extends ConsumerWidget {
  const SecuritySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final settingsAsync = ref.watch(settingsProvider);
    final canManageSession =
        SessionManager().hasPermission('manage_session_settings');

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
            if (canManageSession) ...[
              const SizedBox(height: 16),
              Text('Session', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'How long the app waits for input before ending the session, '
                'and how early the expiry warning appears.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Inactivity timeout'),
                      subtitle: settingsAsync.when(
                        data: (settings) => Text(
                          SessionSettingsService.inactivityTimeoutLabel(
                            settings.inactivityTimeoutMinutes,
                          ),
                        ),
                        loading: () => const Text('Loading…'),
                        error: (_, _) => const Text('Unable to load'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showInactivityTimeoutDialog(context, ref, settingsAsync),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notification_important_outlined),
                      title: const Text('Session warning'),
                      enabled: (settingsAsync.valueOrNull
                                  ?.inactivityTimeoutMinutes ??
                              15) >
                          SessionSettingsService.unlimitedInactivityMinutes,
                      subtitle: settingsAsync.when(
                        data: (settings) => Text(
                          settings.inactivityTimeoutMinutes <=
                                  SessionSettingsService
                                      .unlimitedInactivityMinutes
                              ? 'Not applicable with an unlimited timeout'
                              : 'Warn ${SessionSettingsService.sessionWarningLabel(settings.sessionWarningSeconds)} before logout',
                        ),
                        loading: () => const Text('Loading…'),
                        error: (_, _) => const Text('Unable to load'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showSessionWarningDialog(context, ref, settingsAsync),
                    ),
                  ],
                ),
              ),
            ],
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
        type: AppDialogType.edit,
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
    // Keep a previously stored custom value selectable so saving never
    // silently rewrites it; sort it in among the finite choices with
    // Unlimited last.
    final choices = [...SessionSettingsService.inactivityTimeoutChoices];
    if (!choices.contains(current)) {
      choices.add(current);
      choices.sort(
        (a, b) => a == 0 ? 1 : b == 0 ? -1 : a.compareTo(b),
      );
    }
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: 'Inactivity Timeout',
        childBuilder: (context, state) {
          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How long the app waits for input before locking. '
                  'Unlimited never locks on idle — the 8-hour maximum session '
                  'length still applies. This setting is global and applies '
                  'to all users.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AppDropdownField<int>(
                  label: 'Timeout',
                  prefixIcon: Icons.timer_outlined,
                  items: [
                    for (final minutes in choices)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          SessionSettingsService.inactivityTimeoutLabel(
                            minutes,
                          ),
                        ),
                      ),
                  ],
                  initialValue: current,
                  onChanged: (value) {
                    state.setValue<int>('timeoutMinutes', value ?? current);
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
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: (dialogContext) async {
              if (!state.formKey.currentState!.validate()) return;

              state.setSaving(true);

              final minutes =
                  state.value<int>('timeoutMinutes', current) ?? current;
              final settings = settingsAsync.valueOrNull;
              if (settings == null) {
                state.setSaving(false);
                return;
              }

              final updated = await ref
                  .read(settingsServiceProvider)
                  .updateSessionSettings(
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

  Future<void> _showSessionWarningDialog(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Settings> settingsAsync,
  ) async {
    final currentSettings = settingsAsync.valueOrNull;
    final current = currentSettings?.sessionWarningSeconds ?? 30;
    // The warning must always be shorter than the inactivity timeout, so
    // choices are filtered against it. (An unlimited timeout disables the
    // tile, so this dialog is unreachable then.)
    final timeoutMinutes = currentSettings?.inactivityTimeoutMinutes ?? 15;
    final choices = SessionSettingsService.sessionWarningChoices
        .where((seconds) => seconds < timeoutMinutes * 60)
        .toList();
    if (!choices.contains(current)) {
      choices.add(current);
      choices.sort();
    }
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: 'Session Warning',
        childBuilder: (context, state) {
          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How long before automatic logout the '
                  '"Session Expiring" warning appears. It always stays '
                  'shorter than the inactivity timeout.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AppDropdownField<int>(
                  label: 'Warn before logout',
                  prefixIcon: Icons.notification_important_outlined,
                  items: [
                    for (final seconds in choices)
                      DropdownMenuItem(
                        value: seconds,
                        child: Text(
                          SessionSettingsService.sessionWarningLabel(seconds),
                        ),
                      ),
                  ],
                  initialValue: current,
                  onChanged: (value) {
                    state.setValue<int>('warningSeconds', value ?? current);
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
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: (dialogContext) async {
              if (!state.formKey.currentState!.validate()) return;

              state.setSaving(true);

              final seconds =
                  state.value<int>('warningSeconds', current) ?? current;
              final settings = settingsAsync.valueOrNull;
              if (settings == null) {
                state.setSaving(false);
                return;
              }

              final updated = await ref
                  .read(settingsServiceProvider)
                  .updateSessionSettings(
                    settings.copyWith(sessionWarningSeconds: seconds),
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
                    message: 'Unable to save the session warning.',
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
        message: 'Session warning updated.',
      );
    }
  }
}
