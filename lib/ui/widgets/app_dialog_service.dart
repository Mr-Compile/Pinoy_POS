import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_messages.dart';

/// Possible user choices from the "Backup Export Failed" dialog.
enum BackupExportFailedResult { close, tryAgain }

enum BackupDestinationConfirmResult { save, cancel }

class AppDialogService {
  AppDialogService._();

  static Future<T?> _show<T>({
    required BuildContext context,
    required AppDialogType type,
    required String title,
    String? message,
    String? details,
    Widget? child,
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
      useSafeArea: true,
      barrierDismissible: dismissible,
      builder: (context) => AppDialog(
        type: type,
        title: title,
        message: message,
        details: details,
        actions: actions,
        dismissible: dismissible,
        child: child,
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
    void Function(BuildContext)? onPrimary,
    String? secondaryLabel,
    void Function(BuildContext)? onSecondary,
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
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
    void Function(BuildContext)? onPrimary,
    String secondaryLabel = 'Close',
    void Function(BuildContext)? onSecondary,
  }) {
    return _show(
      context: context,
      type: AppDialogType.error,
      title: title,
      message: message,
      details: details,
      actions: [
        AppDialogAction(label: secondaryLabel, onPressed: onSecondary ?? (context) => Navigator.of(context, rootNavigator: true).pop()),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
    void Function(BuildContext)? onPrimary,
    String? secondaryLabel,
    void Function(BuildContext)? onSecondary,
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
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
    void Function(BuildContext)? onPrimary,
    String? secondaryLabel,
    void Function(BuildContext)? onSecondary,
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
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
    void Function(BuildContext)? onPrimary,
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
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  static Future<void> accessDenied(
    BuildContext context, {
    void Function(BuildContext)? onPrimary,
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
          onPressed: onPrimary ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: destructive,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Delete Permanently',
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }

  static Future<bool?> logoutConfirm(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.error,
      title: 'Log out?',
      message: AppMessages.logoutConfirm,
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Log Out',
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Discard',
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }

  // ── Void Sale ────────────────────────────────────────────────────────

  static Future<String?> voidSaleConfirm(BuildContext context) {
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => const _VoidSaleDialog(),
    );
  }

  // ── Session Expired ──────────────────────────────────────────────────

  static Future<void> sessionExpired(
    BuildContext context, {
    void Function(BuildContext)? onLogin,
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
          onPressed: onLogin ?? (context) => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
        ),
        AppDialogAction(
          label: 'Continue Offline',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
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
    void Function(BuildContext)? onRetry,
  }) {
    return error(
      context,
      title: title,
      message: message,
      primaryLabel: 'Try Again',
      onPrimary: onRetry == null
          ? null
          : (context) {
              Navigator.of(context, rootNavigator: true).pop();
              onRetry(context);
            },
    );
  }

  // ── Backup: Export Destination Confirmation ──────────────────────────

  /// Shows a confirmation dialog with the selected backup destination
  /// before the backup file is actually written.
  ///
  /// Returns [BackupDestinationConfirmResult.save] if the user wants to save
  /// to the current location, or [cancel] if they abort. Location changes
  /// are handled from the Backup & Restore screen, not inside this modal.
  static Future<BackupDestinationConfirmResult> backupDestinationConfirm(
    BuildContext context, {
    required String displayName,
    required String location,
  }) {
    return _show<BackupDestinationConfirmResult>(
      context: context,
      type: AppDialogType.info,
      title: 'Create Backup',
      message: 'Please confirm the backup destination.',
      details: 'File: $displayName\nLocation: $location',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(
            context,
            rootNavigator: true,
          ).pop(BackupDestinationConfirmResult.cancel),
        ),
        AppDialogAction(
          label: 'Create Backup',
          isPrimary: true,
          onPressed: (context) => Navigator.of(
            context,
            rootNavigator: true,
          ).pop(BackupDestinationConfirmResult.save),
        ),
      ],
    ).then((v) => v ?? BackupDestinationConfirmResult.cancel);
  }

  // ── Backup: Export Success ───────────────────────────────────────────

  static Future<void> backupExportSuccess(
    BuildContext context, {
    required String displayName,
    required String location,
    String? fileSize,
  }) {
    return success(
      context,
      title: 'Backup Created Successfully',
      message: 'Your Pinoy POS backup was saved successfully.',
      details: 'File: $displayName\nLocation: $location${fileSize != null ? '\nSize: $fileSize' : ''}',
      primaryLabel: 'Done',
    );
  }

  // ── Backup: Export Failed ────────────────────────────────────────────

  static Future<BackupExportFailedResult> backupExportFailed(
    BuildContext context, {
    String? reason,
  }) {
    return _show<BackupExportFailedResult>(
      context: context,
      type: AppDialogType.error,
      title: 'Backup Failed',
      message: 'We couldn\'t create the backup.',
      details: reason,
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (context) => Navigator.of(context, rootNavigator: true)
              .pop(BackupExportFailedResult.close),
        ),
        AppDialogAction(
          label: 'Try Again',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true)
              .pop(BackupExportFailedResult.tryAgain),
        ),
      ],
    ).then((v) => v ?? BackupExportFailedResult.close);
  }

  // ── Backup: Location Required ────────────────────────────────────────

  /// Shown when the Admin tries to export a backup but no backup location
  /// has been configured yet.
  ///
  /// Returns true if the user chooses to pick a location, false on cancel.
  static Future<bool> backupLocationRequired(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.info,
      title: 'Backup Location Required',
      message:
          'Choose where you want future Pinoy POS backups to be saved.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Choose Location',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    ).then((v) => v ?? false);
  }

  // ── Backup: Location Unavailable ─────────────────────────────────────

  /// Shown when the previously saved backup location can no longer be
  /// accessed (permission revoked, folder moved/deleted, etc.).
  ///
  /// Returns true if the user chooses to pick a new location, false on
  /// cancel.
  static Future<bool> backupLocationUnavailable(BuildContext context) {
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Backup Location Unavailable',
      message:
          'The previously selected backup location can no longer be '
          'accessed. Please choose a new location.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Choose New Location',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    ).then((v) => v ?? false);
  }

  // ── Backup: Location Selection Failed ────────────────────────────────

  static Future<bool> backupLocationSelectionFailed(
    BuildContext context, {
    String? reason,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.error,
      title: 'Location Selection Failed',
      message: 'We couldn\'t set the backup location.',
      details: reason,
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Try Again',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    ).then((v) => v ?? false);
  }

  // ── Backup: Location Changed ─────────────────────────────────────────

  static Future<void> backupLocationChanged(
    BuildContext context, {
    required String location,
  }) {
    return success(
      context,
      title: 'Backup Location Updated',
      message: 'Future backups will be saved to the new location.',
      details: location,
      primaryLabel: 'Done',
    );
  }

  // ── Backup: Restore Confirmation ─────────────────────────────────────

  static Future<bool?> restoreBackupConfirm(
    BuildContext context, {
    String? displayName,
    String? fileSize,
  }) {
    final info = StringBuffer()
      ..writeln('Restoring this backup may replace the current Pinoy POS data.')
      ..writeln('Make sure you have created a recent backup before continuing.');
    if (displayName != null) {
      info.writeln('\nFile: $displayName');
    }
    if (fileSize != null) {
      info.writeln('Size: $fileSize');
    }
    return _show<bool>(
      context: context,
      type: AppDialogType.warning,
      title: 'Restore Backup?',
      message: info.toString(),
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Restore',
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }

  // ── Backup: Restore Success ──────────────────────────────────────────

  static Future<void> backupRestoreSuccess(BuildContext context) {
    return success(
      context,
      title: 'Backup Restored Successfully',
      message: 'Your data has been restored successfully.\nThe application will refresh to load the restored data.',
      primaryLabel: 'Continue',
    );
  }

  // ── Backup: Restore Failed ───────────────────────────────────────────

  static Future<void> backupRestoreFailed(
    BuildContext context, {
    String? reason,
  }) {
    return error(
      context,
      title: 'Restore Failed',
      message: reason != null && reason.isNotEmpty
          ? 'Failed to restore the backup: $reason'
          : 'Failed to restore the backup. The file may be corrupt or incompatible.',
    );
  }

  // ── Backup: Invalid File ─────────────────────────────────────────────

  static Future<void> invalidBackupFile(BuildContext context) {
    return error(
      context,
      title: 'Invalid Backup File',
      message: 'The selected file is not a valid Pinoy POS backup or cannot be restored.',
      primaryLabel: 'Choose Another File',
    );
  }

  // ── Backup: Incompatible ─────────────────────────────────────────────

  static Future<void> incompatibleBackupFile(BuildContext context) {
    return error(
      context,
      title: 'Incompatible Backup',
      message: 'This backup file does not contain the required Pinoy POS data tables and cannot be restored.',
      primaryLabel: 'Choose Another File',
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Deactivate',
          isPrimary: true,
          isDestructive: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
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
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Confirm',
          isPrimary: true,
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
  }

  // ── AI: Not Configured (Owner sees this) ──────────────────────────────

  static Future<void> aiNotConfigured(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.info,
      title: 'AI Advisor Not Configured',
      message:
          'The AI service has not been configured yet. Please ask your administrator to configure the Groq AI integration.',
      actions: [
        AppDialogAction(
          label: 'Done',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  // ── AI: Needs Internet ────────────────────────────────────────────────

  static Future<void> aiNeedsInternet(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.warning,
      title: 'AI Advisor Needs Internet',
      message:
          'Your business data is available locally, but an internet connection is required to generate AI insights.',
      actions: [
        AppDialogAction(
          label: 'Close',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  // ── AI: Daily Limit Reached ───────────────────────────────────────────

  static Future<void> aiDailyLimitReached(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.info,
      title: 'Daily AI Limit Reached',
      message:
          'You have used all 10 AI Advisor queries for today. Your limit will reset tomorrow.',
      actions: [
        AppDialogAction(
          label: 'Done',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  // ── AI: Model Unavailable (Owner sees this) ───────────────────────────

  static Future<void> aiModelUnavailable(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.warning,
      title: 'AI Advisor Temporarily Unavailable',
      message:
          'The configured AI model needs to be updated by an administrator.',
      actions: [
        AppDialogAction(
          label: 'Close',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  // ── AI: Model Unavailable (Admin sees this) ───────────────────────────

  static Future<void> aiModelUnavailableAdmin(BuildContext context) {
    return _show(
      context: context,
      type: AppDialogType.warning,
      title: 'Selected Model Unavailable',
      message:
          'The currently selected AI model is no longer available on Groq. Please choose another available model.',
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  // ── AI: Test Connection Result ────────────────────────────────────────

  static Future<void> aiTestConnectionResult(
    BuildContext context, {
    required bool isConnected,
    String? message,
  }) {
    if (isConnected) {
      return success(
        context,
        title: 'Connection Successful',
        message: message ?? 'Connected to Groq.',
        primaryLabel: 'Done',
      );
    }
    return error(
      context,
      title: 'Connection Failed',
      message: message ?? 'Could not connect to Groq.',
      primaryLabel: 'Done',
    );
  }

  // ── AI: Refresh Models Failed ─────────────────────────────────────────

  static Future<bool> aiRefreshModelsFailed(
    BuildContext context, {
    String? reason,
  }) {
    return _show<bool>(
      context: context,
      type: AppDialogType.error,
      title: 'Refresh Failed',
      message: 'Could not fetch the latest models from Groq.',
      details: reason,
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(false),
        ),
        AppDialogAction(
          label: 'Try Again',
          isPrimary: true,
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    ).then((v) => v ?? false);
  }
}

class _VoidSaleDialog extends StatefulWidget {
  const _VoidSaleDialog();

  @override
  State<_VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<_VoidSaleDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reasonController.text.trim();
    final voidEnabled = reason.isNotEmpty;

    return AppDialog(
      type: AppDialogType.warning,
      title: 'Void Sale?',
      message:
          'Voiding a sale reverses the transaction. This action cannot be undone.',
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
        ),
        AppDialogAction(
          label: 'Void Sale',
          isPrimary: true,
          isDestructive: true,
          onPressed: voidEnabled
              ? (context) => Navigator.of(context, rootNavigator: true)
                  .pop(_reasonController.text.trim())
              : null,
        ),
      ],
      child: AppTextFormField(
        controller: _reasonController,
        label: 'Reason',
        maxLines: 2,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
