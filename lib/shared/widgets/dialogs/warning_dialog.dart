import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// A warning dialog with an amber warning icon.
///
/// Returns `true` when the user confirms, `false` when they cancel.
///
/// Example:
/// ```dart
/// final confirmed = await WarningDialog.show(
///   context: context,
///   title: 'Unsaved Changes',
///   message: 'You have unsaved changes. Leave anyway?',
/// );
/// if (confirmed == true) Navigator.pop(context);
/// ```
class WarningDialog extends StatelessWidget {
  const WarningDialog({super.key});

  /// Shows a warning dialog. Returns `true` if confirmed, `false` if cancelled.
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    String? message,
    String confirmAction = 'Confirm',
    String cancelAction = 'Cancel',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value(false);

    return AppDialog.show<bool>(
      context: context,
      title: title,
      message: message,
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFD97706),
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
          child: Text(confirmAction),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
