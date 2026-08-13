import 'package:flutter/material.dart';

import '../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../shared/widgets/dialogs/error_dialog.dart';
import '../../shared/widgets/dialogs/info_dialog.dart';
import '../../shared/widgets/dialogs/loading_dialog.dart';
import '../../shared/widgets/dialogs/no_internet_dialog.dart';
import '../../shared/widgets/dialogs/success_dialog.dart';
import '../../shared/widgets/dialogs/warning_dialog.dart';

/// Static facade for showing all app dialogs via easy one-liner calls.
///
/// Use this instead of `ScaffoldMessenger` or inline `showDialog` calls.
///
/// Every method checks `context.mounted` before showing a dialog, so it is
/// safe to call after `await`. All dialogs are centered on screen with a
/// fade + scale animation, theme-aware, and responsive (tablet vs phone).
/// No global [BuildContext] is stored anywhere.
class DialogService {
  DialogService._();

  /// Shows a success dialog.
  static Future<void> showSuccess(
    BuildContext context,
    String message, {
    String title = 'Success',
    VoidCallback? onAcknowledge,
  }) {
    if (!context.mounted) return Future.value();
    return SuccessDialog.show(
      context: context,
      title: title,
      message: message,
      actionLabel: 'OK',
      onAction: onAcknowledge,
    );
  }

  /// Shows an error dialog.
  static Future<void> showError(
    BuildContext context,
    String message, {
    String title = 'Error',
    VoidCallback? onAcknowledge,
    String primaryAction = 'Try Again',
    String secondaryAction = 'Close',
    VoidCallback? onPrimaryAction,
    VoidCallback? onSecondaryAction,
  }) {
    if (!context.mounted) return Future.value();
    return ErrorDialog.show(
      context: context,
      title: title,
      message: message,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      onPrimaryAction: onPrimaryAction ?? onAcknowledge,
      onSecondaryAction: onSecondaryAction,
    );
  }

  /// Shows a warning dialog. Returns `true` if confirmed, `false` if cancelled.
  static Future<bool?> showWarning(
    BuildContext context,
    String message, {
    String title = 'Warning',
    String confirmAction = 'Confirm',
    String cancelAction = 'Cancel',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) {
    if (!context.mounted) return Future.value(false);
    return WarningDialog.show(
      context: context,
      title: title,
      message: message,
      confirmAction: confirmAction,
      cancelAction: cancelAction,
      onConfirm: onConfirm,
      onCancel: onCancel,
    );
  }

  /// Shows an info dialog.
  static Future<void> showInfo(
    BuildContext context,
    String message, {
    String title = 'Info',
    VoidCallback? onAcknowledge,
  }) {
    if (!context.mounted) return Future.value();
    return InfoDialog.show(
      context: context,
      title: title,
      message: message,
      actionLabel: 'Got It',
      onAction: onAcknowledge,
    );
  }

  /// Shows a confirmation dialog. Returns `true` if confirmed, `false` if cancelled.
  static Future<bool?> showConfirmation(
    BuildContext context,
    String message, {
    String title = 'Confirm',
    String confirmAction = 'Confirm',
    String cancelAction = 'Cancel',
    bool isDestructive = false,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) {
    if (!context.mounted) return Future.value(false);
    return ConfirmationDialog.show(
      context: context,
      title: title,
      message: message,
      confirmAction: confirmAction,
      cancelAction: cancelAction,
      isDestructive: isDestructive,
      onConfirm: onConfirm,
      onCancel: onCancel,
    );
  }

  /// Shows a no-internet dialog.
  static Future<void> showNoInternet(
    BuildContext context, {
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) {
    if (!context.mounted) return Future.value();
    return NoInternetDialog.show(
      context: context,
      onRetry: onRetry,
      onClose: onClose,
    );
  }

  /// Shows a loading dialog and returns a controller to dismiss it.
  static LoadingDialogController showLoading(
    BuildContext context, {
    String? message,
    bool barrierDismissible = false,
  }) {
    if (!context.mounted) return LoadingDialogController.noop();
    return LoadingDialog.show(
      context: context,
      message: message,
      barrierDismissible: barrierDismissible,
    );
  }

  /// Shows a friendly "AI limit reached" dialog.
  static Future<void> showQuotaExceeded(BuildContext context) {
    if (!context.mounted) return Future.value();
    return ErrorDialog.show(
      context: context,
      title: 'AI Limit Reached',
      message:
          "You've reached your daily AI generation limit. Please try again tomorrow.",
      primaryAction: 'OK',
      secondaryAction: '',
    );
  }

  /// Converts a technical error message into a user-friendly one.
  static String getFriendlyErrorMessage(String technicalMessage) {
    final lower = technicalMessage.toLowerCase();
    if (lower.contains('exact alarm not permitted')) {
      return 'Study reminders are not available on this device right now.';
    }
    if (lower.contains('token limit') || lower.contains('quota')) {
      return "You have reached today's AI generation limit.";
    }
    if (lower.contains('no overlay') || lower.contains('overlay widget')) {
      return 'Something went wrong while showing this message. Please try again.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Please check your internet connection and try again.';
    }
    if (lower.contains('permission')) {
      return 'The app needs permission to complete this action.';
    }
    if (lower.contains('storage') || lower.contains('disk')) {
      return 'Please check your available storage and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  /// Shows an error dialog with a friendly version of [technicalMessage].
  static Future<void> showFriendlyError(
    BuildContext context,
    String technicalMessage, {
    String? title,
    VoidCallback? onAcknowledge,
  }) {
    final friendly = getFriendlyErrorMessage(technicalMessage);
    return showError(
      context,
      friendly,
      title: title ?? 'Something Went Wrong',
      onAcknowledge: onAcknowledge,
    );
  }
}
