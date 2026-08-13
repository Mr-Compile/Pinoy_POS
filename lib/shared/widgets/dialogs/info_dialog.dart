import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// An info dialog with a blue info icon.
///
/// Example:
/// ```dart
/// InfoDialog.show(
///   context: context,
///   title: 'New Feature',
///   message: 'You can now export your data as a PDF.',
///   onAction: () => openExportScreen(),
/// );
/// ```
class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key});

  /// Shows an info dialog.
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    String actionLabel = 'Got It',
    VoidCallback? onAction,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value();

    return AppDialog.show(
      context: context,
      title: title,
      message: message,
      icon: Icons.info_outline_rounded,
      iconColor: const Color(0xFF2563EB),
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
