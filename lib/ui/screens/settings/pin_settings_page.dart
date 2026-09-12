import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/safe_navigation.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/settings/set_pin_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

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
                    onTap: () => SafeNavigator.pushUnique<void>(
                      context,
                      const SetPinScreen(),
                    ),
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

  Future<void> _showRemovePinDialog(
      BuildContext context, WidgetRef ref, User user) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.warning,
        title: 'Remove PIN',
        message:
            'Are you sure you want to remove your PIN? '
            'You will need to log in with your password each time.',
        childBuilder: (context, state) => const SizedBox.shrink(),
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (context) async {
                    if (state.hasChanges) {
                      final discard =
                          await AppDialogService.unsavedChanges(context);
                      if (discard == true) {
                        state.pop(const ModalResult<void>.cancelled());
                      }
                    } else {
                      state.pop(const ModalResult<void>.cancelled());
                    }
                  },
          ),
          AppDialogAction(
            label: 'Remove',
            isPrimary: true,
            isDestructive: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (context) => _removePin(context, ref, state, user),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (result?.isSaved ?? false) {
      await AppDialogService.success(
        context,
        title: 'PIN Removed',
        message: 'Your PIN has been removed.',
      );
    }
  }

  Future<void> _removePin(
    BuildContext dialogContext,
    WidgetRef ref,
    AppDialogFormState<ModalResult<void>> state,
    User user,
  ) async {
    state.setSaving(true);

    final success = await ref.read(authStateProvider.notifier).updateProfile(
          userId: user.id!,
          fullName: user.fullName,
          pin: '',
        );

    if (!dialogContext.mounted) return;

    if (success) {
      state.pop(const ModalResult<void>.saved());
    } else {
      state.setSaving(false);
      await AppDialogService.error(
        dialogContext,
        title: 'Update Failed',
        message: 'Failed to remove PIN.',
      );
    }
  }
}
