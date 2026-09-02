import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// PIN settings sub-page — set or clear a login PIN.
///
/// Accessible from the Settings hub. Available to all authenticated
/// users (users can always manage their own PIN).
class PinSettingsPage extends ConsumerWidget {
  const PinSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (user == null) {
      return Scaffold(
        appBar: const AppHeader(title: 'PIN', showBackButton: true),
        body: const Center(child: Text('No user logged in')),
      );
    }

    final hasPin = user.hasPin;

    return Scaffold(
      appBar: const AppHeader(title: 'PIN', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Login PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'A PIN allows quick login without typing your full password. '
              'Set a 4-6 digit PIN or clear it to remove quick login.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Set / Change PIN'),
                    subtitle: Text(hasPin
                        ? 'PIN is set (${user.configuredPinLength} digits)'
                        : 'No PIN set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showSetPinDialog(context, ref, user),
                  ),
                  if (hasPin) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.lock_open_outlined),
                      title: const Text('Remove PIN'),
                      subtitle: const Text('Disable quick login'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showRemovePinDialog(context, ref, user),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSetPinDialog(BuildContext context, WidgetRef ref, User user) {
    final formKey = GlobalKey<FormState>();
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          type: AppDialogType.info,
          title: 'Set PIN',
          actions: [
            AppDialogAction(
              label: 'Cancel',
              onPressed: (context) =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
            AppDialogAction(
              label: 'Save',
              isPrimary: true,
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : (context) async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => isSaving = true);
                      final success = await ref
                          .read(authStateProvider.notifier)
                          .updateProfile(
                            userId: user.id!,
                            fullName: user.fullName,
                            pin: pinController.text.trim(),
                          );
                      if (context.mounted) {
                        setState(() => isSaving = false);
                        if (success) {
                          await AppDialogService.success(
                            context,
                            title: 'PIN Updated',
                            message: 'Your PIN has been set successfully.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                        } else {
                          await AppDialogService.error(
                            context,
                            title: 'Update Failed',
                            message: 'Failed to update PIN.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                      }
                    },
            ),
          ],
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter a 4-6 digit PIN.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: pinController,
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    validator: (value) => Validators.pin(value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please confirm your PIN';
                      }
                      if (value != pinController.text) {
                        return 'PINs do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRemovePinDialog(BuildContext context, WidgetRef ref, User user) {
    bool isSaving = false;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          type: AppDialogType.warning,
          title: 'Remove PIN',
          message:
              'Are you sure you want to remove your PIN? '
              'You will need to log in with your password each time.',
          actions: [
            AppDialogAction(
              label: 'Cancel',
              onPressed: (context) =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
            AppDialogAction(
              label: 'Remove',
              isPrimary: true,
              isDestructive: true,
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : (context) async {
                      setState(() => isSaving = true);
                      final success = await ref
                          .read(authStateProvider.notifier)
                          .updateProfile(
                            userId: user.id!,
                            fullName: user.fullName,
                            pin: '',
                          );
                      if (context.mounted) {
                        setState(() => isSaving = false);
                        if (success) {
                          await AppDialogService.success(
                            context,
                            title: 'PIN Removed',
                            message: 'Your PIN has been removed.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                        } else {
                          await AppDialogService.error(
                            context,
                            title: 'Update Failed',
                            message: 'Failed to remove PIN.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
