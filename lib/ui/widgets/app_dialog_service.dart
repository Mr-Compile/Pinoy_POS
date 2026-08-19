import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
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
      // Always use the root navigator so dialog dismissal via
      // Navigator.of(context, rootNavigator: true).pop() targets the
      // correct route. Without this, a dialog shown from inside a
      // nested Navigator (e.g. inside an inner Scaffold) could pop the
      // wrong route, leaving the dialog stuck open.
      useRootNavigator: true,
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
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
        AppDialogAction(label: secondaryLabel, onPressed: onSecondary ?? () => Navigator.of(context, rootNavigator: true).pop()),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: onPrimary ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: destructive,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Delete Permanently',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Log Out',
          isPrimary: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Discard',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }

  // ── Void Sale ────────────────────────────────────────────────────────

  static Future<String?> voidSaleConfirm(BuildContext context) {
    final reasonController = TextEditingController();
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Semantics(
          label: 'Confirmation required',
          container: true,
          child: Dialog(
            backgroundColor: cs.surface,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 480.0 : double.infinity),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.warning, size: 32, color: cs.secondary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Void Sale?',
                        style: AppTypography.headlineSmallSemibold(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Voiding a sale reverses the transaction. This action cannot be undone.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: reasonController,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                        maxLines: 2,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 24),
                      if (isTablet)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
                              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: reasonController.text.trim().isEmpty
                                  ? null
                                  : () => Navigator.of(context, rootNavigator: true).pop(reasonController.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                                minimumSize: const Size(88, 48),
                              ),
                              child: const Text('Void Sale'),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
                              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: reasonController.text.trim().isEmpty
                                  ? null
                                  : () => Navigator.of(context, rootNavigator: true).pop(reasonController.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                                minimumSize: const Size(88, 48),
                              ),
                              child: const Text('Void Sale'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
          onPressed: onLogin ?? () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        AppDialogAction(
          label: 'Continue Offline',
          isPrimary: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Deactivate',
          isPrimary: true,
          isDestructive: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }
}
