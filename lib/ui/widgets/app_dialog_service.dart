import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_messages.dart';

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

  // ── Success ──────────────────────────────────────────────────────────

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

  // ── Error ────────────────────────────────────────────────────────────

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

  // ── Warning ──────────────────────────────────────────────────────────

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

  // ── Info ─────────────────────────────────────────────────────────────

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

  // ── Restriction / Access Denied ──────────────────────────────────────

  static Future<void> restriction(
    BuildContext context, {
    String title = 'Action not available',
    String message = AppMessages.accessDenied,
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

  static Future<void> accessDenied(
    BuildContext context, {
    VoidCallback? onPrimary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.restriction,
      title: 'Action not available',
      message: AppMessages.accessDenied,
      details: AppMessages.accessDeniedHint,
      actions: [
        AppDialogAction(
          label: 'Close',
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // ── Confirmation ─────────────────────────────────────────────────────

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

  static Future<bool?> permanentDeleteConfirm(
    BuildContext context, {
    required String itemName,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Permanently Delete?',
      message: '$itemName will be permanently deleted.\nThis action cannot be undone.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Delete Permanently',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  static Future<bool?> restoreConfirm(
    BuildContext context, {
    required String itemName,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.confirmation,
      title: 'Restore from Trash?',
      message: 'Restore "$itemName" from trash? It will become active again.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
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
      message: AppMessages.logoutConfirm,
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

  static Future<bool?> unsavedChanges(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Unsaved Changes',
      message: 'You have unsaved changes. Discard them and close?',
      actions: [
        AppDialogAction(
          label: 'Keep Editing',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Discard',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  static Future<bool?> emptyCart(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Cart is Empty',
      message: 'Add at least one product before checking out.',
      actions: [
        AppDialogAction(
          label: 'OK',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  // ── Void Sale ────────────────────────────────────────────────────────

  static Future<String?> voidSaleConfirm(BuildContext context) {
    final reasonController = TextEditingController();

    return _show<String>(
      context: context,
      type: AppDialogType.warning,
      title: 'Void Sale?',
      message: 'Voiding a sale reverses the transaction. This action cannot be undone.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        AppDialogAction(
          label: 'Void Sale',
          isPrimary: true,
          isDestructive: true,
          onPressed: () {
            final reason = reasonController.text.trim();
            Navigator.of(context).pop(reason.isEmpty ? 'No reason provided' : reason);
          },
        ),
      ],
    );
  }

  // ── Session Expired ──────────────────────────────────────────────────

  static Future<void> sessionExpired(
    BuildContext context, {
    VoidCallback? onLogin,
  }) {
    return _show(
      context: context,
      type: AppDialogType.warning,
      title: 'Session Ended',
      message: AppMessages.sessionExpired,
      dismissible: false,
      actions: [
        AppDialogAction(
          label: 'Sign In Again',
          isPrimary: true,
          onPressed: onLogin ?? () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // ── Validation ───────────────────────────────────────────────────────

  static Future<void> validation(
    BuildContext context, {
    required String title,
    required String message,
    String? details,
  }) {
    return _show(
      context: context,
      type: AppDialogType.validation,
      title: title,
      message: message,
      details: details,
      actions: [
        AppDialogAction(
          label: 'Fix',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // ── Offline ──────────────────────────────────────────────────────────

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

  // ── Loading ──────────────────────────────────────────────────────────

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

  // ── Database Error ───────────────────────────────────────────────────

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

  // ── Restore Backup Warning ───────────────────────────────────────────

  static Future<bool?> restoreBackupConfirm(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Restore Backup?',
      message:
          'Restoring will replace all current data with the backup.\n'
          'Please restart the app after restoring.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  // ── Deactivate User ──────────────────────────────────────────────────

  static Future<bool?> deactivateUserConfirm(
    BuildContext context, {
    required String userName,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Deactivate User?',
      message: '$userName will no longer be able to log in.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Deactivate',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  // ── Adjust Stock Confirm ─────────────────────────────────────────────

  static Future<bool?> adjustStockConfirm(
    BuildContext context, {
    required String productName,
    required int adjustment,
    required int newStock,
  }) {
    final isAdd = adjustment > 0;
    return _show<bool>(
      context: context,
      type: AppDialogType.confirmation,
      title: 'Adjust Stock',
      message: isAdd
          ? 'Add $adjustment to "$productName"?\nNew stock: $newStock'
          : 'Remove ${-adjustment} from "$productName"?\nNew stock: $newStock',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  // ── Toggle Category Status ───────────────────────────────────────────

  static Future<bool?> toggleCategoryConfirm(
    BuildContext context, {
    required String categoryName,
    required bool isActivate,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.confirmation,
      title: isActivate ? 'Activate Category' : 'Deactivate Category',
      message: '${isActivate ? "Activate" : "Deactivate"} "$categoryName"?',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
