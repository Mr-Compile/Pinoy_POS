import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
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

  void _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) {
    final formKey = GlobalKey<FormState>();
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isSaving = false;
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool newPasswordTouched = false;
    bool confirmPasswordTouched = false;
    final screenContext = context;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final strengthResult = PasswordStrengthService.evaluate(
            password: newPasswordController.text,
            username: user.username,
          );

          return AlertDialog(
            title: const Text('Change Password'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: oldPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureOld
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => obscureOld = !obscureOld),
                          tooltip: obscureOld
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      obscureText: obscureOld,
                      autofocus: true,
                      validator: (value) =>
                          Validators.required(value, 'Current password'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => obscureNew = !obscureNew),
                          tooltip: obscureNew
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      obscureText: obscureNew,
                      onChanged: (value) {
                        setState(() => newPasswordTouched = true);
                      },
                      validator: (value) {
                        if (!newPasswordTouched) return null;
                        if (value == null || value.isEmpty) {
                          return 'Enter a new password.';
                        }
                        return PasswordStrengthService.validate(
                          password: value,
                          username: user.username,
                          currentPassword: oldPasswordController.text,
                        );
                      },
                    ),
                    if (newPasswordController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      PasswordStrengthMeter(result: strengthResult),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => obscureConfirm = !obscureConfirm),
                          tooltip: obscureConfirm
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      obscureText: obscureConfirm,
                      onChanged: (value) {
                        setState(() => confirmPasswordTouched = true);
                      },
                      validator: (value) {
                        if (!confirmPasswordTouched) return null;
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password.';
                        }
                        if (value != newPasswordController.text) {
                          return 'Your passwords don\'t match.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
                child: const Text('Cancel'),
              ),
              LoadingButton(
                isLoading: isSaving,
                onPressed: () async {
                  setState(() {
                    newPasswordTouched = true;
                    confirmPasswordTouched = true;
                  });
                  if (!formKey.currentState!.validate()) return;
                  setState(() => isSaving = true);
                  final result = await ref
                      .read(userControllerProvider.notifier)
                      .changePassword(
                        userId: user.id!,
                        oldPassword: oldPasswordController.text,
                        newPassword: newPasswordController.text,
                      );
                  if (context.mounted) {
                    setState(() => isSaving = false);
                    if (result.success) {
                      oldPasswordController.clear();
                      newPasswordController.clear();
                      confirmPasswordController.clear();
                      await AppDialogService.success(
                        screenContext,
                        title: 'Password Changed',
                        message: result.message,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context, rootNavigator: true).pop();
                    } else {
                      await AppDialogService.error(
                        screenContext,
                        title: 'Change Failed',
                        message: result.message,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context, rootNavigator: true).pop();
                    }
                  }
                },
                label: 'Change',
              ),
            ],
          );
        },
      ),
    );
  }
}
