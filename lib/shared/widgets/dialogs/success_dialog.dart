import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// A success dialog with a green check-circle icon.
///
/// Example:
/// ```dart
/// SuccessDialog.show(
///   context: context,
///   title: 'Saved',
///   message: 'Your changes have been saved successfully.',
///   onAction: () => Navigator.pop(context),
/// );
/// ```
class SuccessDialog extends StatelessWidget {
  const SuccessDialog({super.key});

  /// Shows a success dialog.
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    String actionLabel = 'OK',
    VoidCallback? onAction,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value();

    return AppDialog.show(
      context: context,
      title: title,
      message: message,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF059669),
      barrierDismissible: barrierDismissible,
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onAction?.call();
          },
          child: Text(actionLabel),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
