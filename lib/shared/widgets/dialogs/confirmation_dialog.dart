import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// A confirmation dialog with a help-outline icon.
///
/// Returns `true` when the user confirms, `false` when they cancel.
/// Set [isDestructive] to `true` for delete/remove actions — the confirm
/// button will be styled with the error color.
///
/// Example (destructive delete):
/// ```dart
/// final confirmed = await ConfirmationDialog.show(
///   context: context,
///   title: 'Delete Item?',
///   message: 'This action cannot be undone.',
///   confirmAction: 'Delete',
///   isDestructive: true,
///   onConfirm: () => deleteItem(),
/// );
/// ```
class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({super.key});

  /// Shows a confirmation dialog. Returns `true` if confirmed, `false` if cancelled.
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    String? message,
    String confirmAction = 'Confirm',
    String cancelAction = 'Cancel',
    bool isDestructive = false,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value(false);

    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isDestructive ? colorScheme.error : colorScheme.primary;

    return AppDialog.show<bool>(
      context: context,
      title: title,
      message: message,
      icon: Icons.help_outline_rounded,
      iconColor: iconColor,
      barrierDismissible: barrierDismissible,
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.pop(context, false);
            onCancel?.call();
          },
          child: Text(cancelAction),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
            onConfirm?.call();
          },
          style: isDestructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                )
              : null,
          child: Text(confirmAction),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
