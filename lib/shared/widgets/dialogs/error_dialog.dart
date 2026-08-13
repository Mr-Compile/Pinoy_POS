import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// An error dialog with a red error-outline icon.
///
/// Example:
/// ```dart
/// ErrorDialog.show(
///   context: context,
///   title: 'Upload Failed',
///   message: 'We could not upload your file. Please try again.',
///   onPrimaryAction: () => retryUpload(),
/// );
/// ```
class ErrorDialog extends StatelessWidget {
  const ErrorDialog({super.key});

  /// Shows an error dialog with optional primary and secondary actions.
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    String primaryAction = 'Try Again',
    String secondaryAction = 'Close',
    VoidCallback? onPrimaryAction,
    VoidCallback? onSecondaryAction,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value();

    final actions = <Widget>[];

    if (secondaryAction.isNotEmpty) {
      actions.add(
        OutlinedButton(
          onPressed: () {
            Navigator.pop(context);
            onSecondaryAction?.call();
          },
          child: Text(secondaryAction),
        ),
      );
    }

    actions.add(
      ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
          onPrimaryAction?.call();
        },
        child: Text(primaryAction),
      ),
    );

    return AppDialog.show(
      context: context,
      title: title,
      message: message,
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFDC2626),
      barrierDismissible: barrierDismissible,
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
