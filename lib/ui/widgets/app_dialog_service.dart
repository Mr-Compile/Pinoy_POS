import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

class AppDialogService {
  AppDialogService._();

  static Future<T?> _show<T>({
    required BuildContext context,
    required AppDialogType type,
    required String title,
    String? message,
    String? details,
    List<AppDialogAction> actions = const [],
    bool dismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      builder: (context) => AppDialog(
        type: type,
        title: title,
        message: message,
        details: details,
        actions: actions,
        dismissible: dismissible,
      ),
    );
  }

  static Future<void> success(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
    String primaryLabel = 'Done',
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.success,
      title: title,
      message: message,
      details: details,
      actions: [
        if (secondaryLabel != null)
          AppDialogAction(label: secondaryLabel, onPressed: onSecondary),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> error(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
    String primaryLabel = 'Try Again',
    VoidCallback? onPrimary,
    String secondaryLabel = 'Close',
    VoidCallback? onSecondary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.error,
      title: title,
      message: message,
      details: details,
      actions: [
        AppDialogAction(label: secondaryLabel, onPressed: onSecondary ?? () => Navigator.of(context).pop()),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> warning(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
    String primaryLabel = 'OK',
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.warning,
      title: title,
      message: message,
      details: details,
      actions: [
        if (secondaryLabel != null)
          AppDialogAction(label: secondaryLabel, onPressed: onSecondary),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> info(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
    String primaryLabel = 'OK',
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.info,
      title: title,
      message: message,
      details: details,
      actions: [
        if (secondaryLabel != null)
          AppDialogAction(label: secondaryLabel, onPressed: onSecondary),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> restriction(
    BuildContext context, {
    String title = 'Action not available',
    String message = "You don't have permission to perform this action.",
    String? details,
    String primaryLabel = 'Close',
    VoidCallback? onPrimary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.restriction,
      title: title,
      message: message,
      details: details,
      actions: [
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<bool?> confirmation(
    BuildContext context, {
    required String title,
    String? message,
    String? details,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.confirmation,
      title: title,
      message: message,
      details: details,
      actions: [
        AppDialogAction(
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  static Future<bool?> deleteConfirm(
    BuildContext context, {
    required String itemName,
    bool permanent = false,
  }) {
    final title = permanent ? 'Permanently delete?' : 'Move to Trash?';
    final message = permanent
        ? 'This action cannot be undone.'
        : 'This item will be moved to Trash and can be restored later.';
    final confirmLabel = permanent ? 'Delete Permanently' : 'Move to Trash';

    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: title,
      message: '$itemName will be affected.\n$message',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  static Future<bool?> logoutConfirm(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.confirmation,
      title: 'Log out?',
      message: 'Are you sure you want to log out of Pinoy POS?',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Log Out',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  static Future<void> offline(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.offline,
      title: "You're offline",
      message:
          'Your internet connection is unavailable. Core Pinoy POS features continue to work offline.',
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          label: 'Continue Offline',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> loading(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    return _show(
      context: context,
      type: AppDialogType.loading,
      title: title,
      message: message,
      dismissible: false,
    );
  }

  static Future<void> dbError(
    BuildContext context, {
    String title = 'Unable to load your data',
    String message = 'We couldn\'t access the local database right now.',
    VoidCallback? onRetry,
  }) {
    return error(
      context,
      title: title,
      message: message,
      primaryLabel: 'Try Again',
      onPrimary: onRetry,
    );
  }
}
