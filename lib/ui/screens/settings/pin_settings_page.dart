import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

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

    final hasPin = user.pin != null && user.pin!.isNotEmpty;

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
              child: ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Manage PIN'),
                subtitle: Text(hasPin
                    ? 'PIN is set (${user.pin!.length} digits)'
                    : 'No PIN set'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showEditPinDialog(context, ref, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPinDialog(BuildContext context, WidgetRef ref, User user) {
    final formKey = GlobalKey<FormState>();
    final pinController = TextEditingController(text: user.pin ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set PIN'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: pinController,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4-6 digits)',
                      border: OutlineInputBorder(),
                      hintText: 'Leave empty to clear',
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
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
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final pinValue = pinController.text.trim();
                final success = await ref
                    .read(authStateProvider.notifier)
                    .updateProfile(
                      userId: user.id!,
                      fullName: user.fullName,
                      pin: pinValue.isEmpty ? null : pinValue,
                    );
                if (context.mounted) {
                  setState(() => isSaving = false);
                  Navigator.of(context, rootNavigator: true).pop();
                  if (success) {
                    await AppDialogService.success(context,
                        title: 'PIN Updated',
                        message: 'PIN updated successfully.');
                  } else {
                    AppDialogService.error(context,
                        title: 'Update Failed',
                        message: 'Failed to update PIN.');
                  }
                }
              },
              label: 'Save',
            ),
          ],
        ),
      ),
    );
  }
}
