class AppMessages {
  AppMessages._();

  // Authentication
  static const String invalidCredentials = 'Incorrect username or password.';
  static const String invalidPin = 'Incorrect username or PIN.';
  static const String inactiveAccount =
      'This account is currently inactive. Please contact an administrator.';
  static const String authError = 'Unable to sign in right now. Please try again.';
  static const String sessionExpired =
      'Your session has ended. Please sign in again to continue.';
  static const String logoutConfirm = 'Are you sure you want to log out of Pinoy POS?';

  // Restriction
  static const String accessDenied =
      "You don't have permission to perform this action.";
  static const String accessDeniedHint =
      'Contact an administrator if you need access.';

  // Validation
  static const String reviewFields = 'Please review the highlighted fields.';
  static const String validationMultiple =
      'Some required information is missing.';

  // Database
  static const String dbLoadError =
      'We couldn\'t access the local database right now.';
  static const String dbSaveError =
      'Something went wrong while saving. Your existing data has not been changed.';
  static const String dbDeleteError =
      'Something went wrong while deleting. Your existing data has not been changed.';

  // Network
  static const String offlineMessage =
      'Your internet connection is unavailable. Core Pinoy POS features continue to work offline.';
  static const String networkRequired =
      'This feature needs an internet connection to continue.';

  // CRUD
  static const String productSaved = 'Product saved successfully.';
  static const String productSaveError = 'Product could not be saved.';
  static const String categorySaved = 'Category saved successfully.';
  static const String categorySaveError = 'Category could not be saved.';
  static const String stockAdded = 'Stock updated successfully.';
  static const String stockAddError = 'Stock could not be updated.';
  static const String saleCompleted = 'Sale completed successfully.';
  static const String saleError = 'Sale could not be completed.';
  static const String profileSaved = 'Profile updated successfully.';
  static const String profileSaveError = 'Profile could not be updated.';
  static const String passwordChanged = 'Password changed successfully.';
  static const String passwordChangeError =
      'Current password is incorrect or new password is too short.';

  // Backup / Restore
  static const String backupCreated = 'Your backup was successfully saved.';
  static const String backupError = 'Backup could not be created.';
  static const String restoreConfirm =
      'This will replace the current local data with the selected backup.';
  static const String restoreCompleted =
      'Your data has been restored successfully.';
  static const String restoreError = 'Restore could not be completed.';

  // Export / Import
  static const String exportCompleted = 'Your report was successfully saved.';
  static const String exportError = 'Report could not be exported.';
  static const String importConfirm =
      'Review the selected file before continuing.';
  static const String importInvalid =
      'The selected file is not a valid Pinoy POS backup.';
  static const String importError = 'Import could not be completed.';

  // Delete
  static const String deleteConfirm = 'This item will be moved to Trash and can be restored later.';
  static const String permanentDeleteConfirm = 'This action cannot be undone.';
  static const String deleteError = 'Item could not be deleted.';

  // Void Sale
  static const String voidSaleReasonRequired =
      'Enter a reason for voiding this sale.';
  static const String voidSaleSuccess = 'Sale voided successfully.';
  static const String voidSaleError = 'Failed to void sale.';

  // Cart
  static const String cartEmpty = 'Add at least one product before completing a sale.';
  static const String insufficientCash =
      'Cash received is less than the total amount due.';

  // Unsaved Changes
  static const String unsavedChanges =
      'You have unsaved changes. Discard them and close?';

  // User CRUD
  static const String userSaved = 'User saved successfully.';
  static const String userSaveError = 'Failed to save user.';
  static const String userDeleted = 'User moved to trash.';
  static const String userDeleteError = 'Failed to delete user.';
  static const String userActivated = 'User activated successfully.';
  static const String userDeactivated = 'User deactivated successfully.';
  static const String userSelfDelete = 'You cannot delete your own account.';
  static const String userSelfDeactivate = 'You cannot deactivate your own account.';
  static const String passwordReset = 'Password reset successfully.';
  static const String passwordResetError = 'Failed to reset password.';

  // Announcement
  static const String announcementSaved = 'Announcement saved successfully.';
  static const String announcementSaveError = 'Failed to save announcement.';
  static const String announcementDeleted = 'Announcement deleted successfully.';
  static const String announcementDeleteError = 'Failed to delete announcement.';

  // Notifications
  static const String notificationMarkedRead = 'Notification marked as read.';
  static const String notificationMarkAllRead = 'All notifications marked as read.';
  static const String notificationMarkReadError = 'Failed to mark notification as read.';
  static const String notificationMarkAllReadError = 'Failed to mark all notifications as read.';

  // Export
  static const String exportCsvSuccess = 'CSV exported successfully.';
  static const String exportCsvError = 'Failed to export CSV.';
  static const String exportPdfSuccess = 'PDF exported successfully.';
  static const String exportPdfError = 'Failed to export PDF.';

  // Restore / Trash
  static const String restoreSuccess = 'Item restored successfully.';
  static const String trashRestoreError = 'Failed to restore item.';
  static const String permanentDeleteSuccess = 'Item permanently deleted.';
  static const String permanentDeleteError = 'Failed to permanently delete item.';

  // Stock
  static const String stockAdjustSuccess = 'Stock adjusted successfully.';
  static const String stockAdjustError = 'Failed to adjust stock.';

  // Category toggle
  static const String categoryActivated = 'Category activated successfully.';
  static const String categoryDeactivated = 'Category deactivated successfully.';
  static const String categoryToggleError = 'Failed to toggle category status.';
}
