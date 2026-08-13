import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// A "No Internet Connection" dialog with a wifi-off icon.
///
/// By default [barrierDismissible] is `false` so the user must pick an action.
///
/// Example:
/// ```dart
/// NoInternetDialog.show(
///   context: context,
///   onRetry: () => refreshData(),
///   onClose: () => Navigator.pop(context),
/// );
/// ```
class NoInternetDialog extends StatelessWidget {
  const NoInternetDialog({super.key});

  /// Shows a no-internet dialog.
  static Future<void> show({
    required BuildContext context,
    VoidCallback? onRetry,
    VoidCallback? onClose,
    bool barrierDismissible = false,
  }) {
    if (!context.mounted) return Future.value();

    return AppDialog.show(
      context: context,
      title: 'No Internet Connection',
      message:
          'This feature requires an internet connection. Please connect to Wi-Fi or mobile data and try again.',
      icon: Icons.wifi_off_rounded,
      iconColor: const Color(0xFFD97706),
      barrierDismissible: barrierDismissible,
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.pop(context);
            onClose?.call();
          },
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onRetry?.call();
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
