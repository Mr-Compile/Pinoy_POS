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
    final cs = Theme.of(context).colorScheme;
    final bgColor = _colorFor(context, type);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Semantics(
          label: _semanticLabel(type),
          child: Row(
            children: [
              Icon(_iconFor(type), color: _iconColorFor(type, cs), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
        backgroundColor: bgColor,
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
    final cs = Theme.of(context).colorScheme;
    switch (type) {
      case FeedbackType.success:
        return cs.tertiary;
      case FeedbackType.error:
        return cs.error;
      case FeedbackType.warning:
        return cs.secondary;
      case FeedbackType.info:
        return cs.primary;
    }
  }

  static Color _iconColorFor(FeedbackType type, ColorScheme cs) {
    switch (type) {
      case FeedbackType.success:
        return cs.onTertiary;
      case FeedbackType.error:
        return cs.onError;
      case FeedbackType.warning:
        return cs.onSecondary;
      case FeedbackType.info:
        return cs.onPrimary;
    }
  }

  static String _semanticLabel(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return 'Success';
      case FeedbackType.error:
        return 'Error';
      case FeedbackType.warning:
        return 'Warning';
      case FeedbackType.info:
        return 'Information';
    }
  }
}
