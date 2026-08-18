import 'package:flutter/material.dart';

enum FeedbackType { success, error, warning, info }

class AppFeedback {
  AppFeedback._();

  static void show(
    BuildContext context,
    String message, {
    FeedbackType type = FeedbackType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_iconFor(type), color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _colorFor(context, type),
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.success);

  static void error(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.error);

  static void warning(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.info);

  static IconData _iconFor(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return Icons.check_circle;
      case FeedbackType.error:
        return Icons.error;
      case FeedbackType.warning:
        return Icons.warning;
      case FeedbackType.info:
        return Icons.info;
    }
  }

  static Color _colorFor(BuildContext context, FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return Colors.green.shade700;
      case FeedbackType.error:
        return Theme.of(context).colorScheme.error;
      case FeedbackType.warning:
        return Colors.orange.shade700;
      case FeedbackType.info:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
