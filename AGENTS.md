# Pinoy POS Agent Notes

## GCash Payment Proof Image Lifecycle Fix

### Root Cause

The GCash proof export could lose its image identity in three places:

1. `ImageService.pickAndStoreImage` validated the picked file by its **filename extension only** and stored it using that extension. Files picked without an extension (or with `.jpeg`) were rejected or stored with an inconsistent canonical type.
2. `FileTypeUtils` only recognised JPEG/PNG/WebP/PDF by magic bytes and did not map `.jpeg`/`.jpe`/`.jfif`/`.tif`/`.heif` to canonical types. HEIC/AVIF/SVG/GIF/BMP were not detected.
3. `PaymentProofService.exportPaymentProofFromPath` (now `exportGcashProofAsImageFromPath`) fell back to the generic extension `.bin` when the file type could not be determined, and it never passed a MIME type to `FileExportService`. `FileExportService` (IO) also ignored `mimeType` and, on mobile, appended the extension to the content URI returned by the picker, which could produce a misleading or extensionless saved file.

Additionally, `BackupService` only copied the SQLite database, so a restore on a new device left `payment_proof_path` rows pointing to missing image files.

### Changes Made

- `lib/core/file_type_utils.dart`
  - Added `FileType` entries for GIF, BMP, TIFF, HEIC, AVIF, SVG.
  - Added magic-byte detection for those formats plus ISOBMFF (`ftyp`) brands for HEIC/AVIF and SVG XML headers.
  - Made `FileType.fromExtension` accept bare extensions (`'jpg'`) and filenames (`'proof.jpg'`), and map `.jpeg`/`.jpe`/`.jfif`, `.tif`, and `.heif` to canonical types.
  - Increased `FileTypeUtils` robustness for no-extension sources.

- `lib/services/image_service.dart`
  - `pickAndStoreImage` now detects the real image type from the file bytes first and stores the file with the **canonical** extension (`jpg`, `png`, `webp`, etc.).
  - No-extension images with valid magic bytes are accepted.
  - `detectFileType` reads 512 bytes (was 64) so HEIC/AVIF/SVG headers are available.

- `lib/services/payment_proof_service.dart`
  - Renamed export methods to `exportGcashProofAsImage` and `exportGcashProofAsImageFromPath` to make the image-only contract explicit.
  - Export filename is now `gcash_proof_sale_<saleId>_<timestamp>.<ext>` (e.g. `gcash_proof_sale_10245_20260902_143522.jpg`).
  - Falls back to `.jpg` for unknown GCash proofs instead of `.bin`.
  - Passes the correct MIME type to `FileExportService`.
  - `resolveImageExtension` is public for testability.

- `lib/services/file_export_service_io.dart`
  - Uses the provided `mimeType` to choose a better `FileType` (`FileType.image`, `FileType.pdf`).
  - On mobile, returns the picker result as-is for content URIs and only renames real local paths; does not append extensions to Android content URIs.

- `lib/services/file_export_service_web.dart`
  - Expanded `_mimeForExtension` to cover all supported image extensions.

- `lib/ui/screens/payment_proof_viewer_screen.dart`
  - Removed `PdfPreview`; GCash proof is always an image.
  - Added a labelled "Download Image" button in the metadata panel.
  - Improved error/missing/corrupted states and dark-mode-safe colours.

- `lib/ui/screens/receipt_screen.dart` and `lib/ui/screens/sale_detail_screen.dart`
  - Proof buttons are now "View Image" and "Download Image".
  - Receipt remains "Download PDF".
  - Removed PDF-specific proof UI paths.

- `lib/services/sales_service.dart`
  - `replacePaymentProof` now moves the replacement proof from the transient `payment_evidence/tmp/` directory into the sale-owned `payment_evidence/sale_$saleId/` directory, detects the image type, and updates `payment_proof_path` and `payment_proof_type` in one transaction.

- `lib/services/receipt_service.dart`
  - Receipt export now passes `mimeType: 'application/pdf'`, preserving the PDF pipeline.
  - `buildFileName` now returns the filename with the `.pdf` extension already included, so the save dialog shows a complete filename.

- `lib/core/database.dart`
  - Database version bumped to 17.
  - v16/v17 migration backfills `payment_proof_type` with the improved 512-byte detection.

- `lib/services/backup_service.dart`
  - Backups are now zip archives containing `pinoy_pos.db` and a `payment_evidence/` directory.
  - Restore extracts the zip, copies the database, and copies `payment_evidence/` into the app documents directory.
  - Legacy `.db` backups are still detected and restored (without evidence files, as before).

- Tests added
  - `test/file_type_utils_test.dart` - 34 unit tests covering extension/MIME mapping and magic-byte detection for all supported formats.
  - `test/payment_proof_service_test.dart` - 9 unit tests for `PaymentProofService.resolveImageExtension` and `PaymentProofInfo` flags.
  - `test/payment_proof_integration_test.dart` - 3 integration tests that write real JPEG and PNG proof files with no extension, then resolve the type from magic bytes and produce the correct canonical extension.
  - `test/backup_service_test.dart` - compile/construct smoke test for the updated `BackupService`.

### Verification

Run the focused test suite:

```powershell
flutter test test/file_type_utils_test.dart test/payment_proof_service_test.dart test/payment_proof_integration_test.dart test/gcash_payment_service_test.dart
```

Result: 55/55 tests passed.

`flutter analyze` reports no issues.

### Receipt PDF Regression Check

`gcash_payment_service_test.dart` includes `receipt PDF is generated with non-zero bytes` and passes. `ReceiptService.saveReceiptToFile` still uses `FileType.custom` / `allowedExtensions: ['pdf']` and now passes `mimeType: 'application/pdf'`, so the PDF export pipeline remains separate from the image proof pipeline.

## Reports, Sales, Dark Mode, and Export Repair Pass

### Root Cause

Several functional and visual issues surfaced during the analytics/receipt audit:

1. `FileExportService` on web created the download `Blob` from the full backing buffer, which could include trailing bytes for a `Uint8List` sub-view, and it revoked the object URL before the browser had time to start the download.
2. `FileExportService` on mobile returned `FileExportCommon.ensureExtension(picked, ...)` for `content://` URIs, producing a misleading path string and possibly corrupting the platform-given URI.
3. `ReportExportService` exported only the 100-row sale preview in `SalesAnalytics.sales`, so reports were missing transactions on busy periods.
4. `SaleItemDao.getTopProducts` used `INNER JOIN products`, which dropped sales of products that were later deleted, and it ignored the historical `sale_items.product_name`.
5. `SalesTransactionsList` showed `Cashier: User N` instead of the staff member's name.
6. `AppSemanticColors.resolve` inverted the HSL lightness of light colors, which does not produce usable dark-mode surfaces and made many status backgrounds appear muddy.
7. `ColorScheme.primary` and `onPrimary` were pinned to the light-mode brand blue in both themes, so primary text/backgrounds did not adapt.
8. `PaymentMethodChart` and `ProfileMenu` used hardcoded `Colors.black`/`Colors.white` or raw `AppSemanticColors.error` instead of theme-aware colors.
9. `SalesAnalyticsScreen` reported export success/failure through `ScaffoldMessenger` instead of the project's `AppDialogService`.

### Changes Made

- `lib/services/file_export_service_web.dart`
  - Copies `bytes.sublist(0)` into a fresh `Uint8List` before building the `Blob` so trailing buffer bytes are not included.
  - Delays `web.URL.revokeObjectURL` by two seconds so the anchor click has time to start the download.

- `lib/services/file_export_service_io.dart`
  - On mobile (Android/iOS) returns the `FilePicker` result unchanged and never appends an extension to a `content://` URI.
  - On desktop still runs `ensureExtension`, creates parent directories, and writes the file.
  - Catches general `Exception` instead of only `FileSystemException`.

- `lib/services/report_export_service.dart`
  - `exportSalesReport` now returns `String?` (the saved path or `null`).
  - Fetches all confirmed sales for the period through `SalesService().getFilteredSales(..., limit: null)` instead of using the 100-row UI preview.

- `lib/services/sales_service.dart` / `lib/data/repositories/sale_repository.dart` / `lib/data/dao/sale_dao.dart`
  - `getFilteredSales` and `getConfirmedSalesForRange` now accept `int? limit = 500`, allowing `null` to disable the cap.

- `lib/data/dao/sale_item_dao.dart`
  - `getTopProducts` uses `LEFT JOIN products` and `COALESCE(si.product_name, p.name, 'Product #' || si.product_id)` for the product name, and groups by the same `COALESCE` expression.

- `lib/ui/widgets/sales_transactions_list.dart` / `lib/ui/screens/sales_analytics_screen.dart`
  - `SalesTransactionsList` accepts a `Map<int, String>? staffNames` and shows the cashier's full name instead of `User N`.
  - `SalesAnalyticsScreen` builds the map from `analytics.staffSummaries`.

- `lib/core/app_theme.dart`
  - `AppSemanticColors.resolve` now uses a `switch` on `Color` with explicit dark-mode variants for every semantic role.
  - `ColorScheme` primary/onPrimary and error family are resolved per brightness.
  - `premiumButtonGradient` resolves `primary` and `primaryLight` so the dark-mode gradient is lighter, not darker.

- `lib/ui/widgets/payment_method_chart.dart`
  - `_contrastColor` uses `colorScheme.surface` and `colorScheme.onSurface` instead of `Colors.black`/`Colors.white`.

- `lib/ui/widgets/profile_menu.dart`
  - Logout icon/text now use `AppSemanticColors.resolve(AppSemanticColors.error, brightness)`.

- `lib/ui/screens/sales_analytics_screen.dart`
  - Export feedback now goes through `AppDialogService.success`, `AppDialogService.warning`, and `AppDialogService.error`, and displays the saved path on success.

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 232/232 tests.

### Remaining Known Gaps

- Currency display is still hardcoded to `₱` in several screens (`pos_screen.dart`, `sales_screen.dart`, `products_screen.dart`, `trash_screen.dart`, etc.). A central `CurrencyUtils` helper and a pass through the POS/product flows is still needed.
- `lib/ui/screens/reports_screen.dart` is dead code and should be removed or rewired.
- The Settings > Reports hub filters (date, staff, payment method) are not yet wired to real filtered export queries.
- Responsive/tablet/desktop break points and visual regressions should be smoke-tested on actual devices after the color palette change.

## Reports Module Staff-to-Owner Workflow

### What Changed

- `lib/core/database.dart`
  - Bumped schema version to 18.
  - Added `status`, `submitted_at`, `viewed_at`, `file_size`, `thumbnail_path`, `report_number`, and `deleted_at` columns to `export_history`.
  - Backfilled old rows to `status = 'generated'`.

- `lib/data/models/export_history.dart`
  - Extended `ExportHistory` to carry status/lifecycle fields.
  - Added `ReportStatus` constants: `generated`, `submitted`, `viewed`, `archived`, `imported`.

- `lib/data/dao/export_history_dao.dart` / `lib/data/repositories/export_history_repository.dart`
  - Added status/creator queries and ordered active results by `created_at DESC`.
  - Fixed `getAllActive` so it no longer crashes on the missing `deleted_at` column.

- `lib/core/session_manager.dart`
  - Added `view_report_submissions` to the Owner permission set.

- `lib/services/report_service.dart`
  - `recordExport` now returns the inserted `export_history` id.
  - Added `submitReport`, `markReportViewed`, `archiveReport`, `getReportById`, `getSubmittedReports`, `getMyReports`, `getReportCreatorName`, and `importReport`.

- `lib/services/report_export_service.dart`
  - `exportSalesReport` records `fileSize` and `reportNumber`.
  - Added `submitSalesReport` for Staff: it generates the report, writes it to the app `reports/` directory, records `export_history`, and marks it as `submitted`.

- `lib/ui/screens/sales_analytics_screen.dart`
  - Staff see a **Submit to Owner** option in the export menu.
  - Export feedback goes through `AppDialogService`.

- `lib/ui/screens/report_submissions_screen.dart` (new)
  - Owner sees staff-submitted reports.
  - Staff see their own report history.
  - Owner can import external PDF/Excel/CSV reports.
  - Supports pull-to-refresh, empty/error/loading states, and status chips.

- `lib/ui/screens/report_preview_screen.dart` (new)
  - Renders PDFs with `PdfPreview`.
  - Renders Excel/CSV as a `DataTable` from the first sheet/first 50 rows.
  - Provides Export and Share actions.

- `lib/ui/screens/more_screen.dart`
  - Added **Submitted Reports** and **My Reports** entries.

- `lib/core/ai_navigation_registry.dart`
  - Added a `report_submissions` AI destination.

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 232/232 tests.

### Remaining Gaps

- `lib/ui/screens/reports_screen.dart` and `lib/providers/reports_provider.dart` remain as dead code. They duplicate the PDF/Excel/CSV logic that now lives in `ReportExportService`. Removing them needs explicit confirmation because the `owner_screens_test` `ReportsScreen builds for owner` test still references the old screen.
- Report thumbnails are not yet generated. `thumbnail_path` is persisted but left `null`.
- The owner export for the owner's own sales only is not a separate filter. Owner exports in `SalesAnalyticsScreen` already cover the selected period and use `SalesAnalyticsService`, which scopes Staff to their own sales and gives Owner the full store view.

## Safe Dialog Lifecycle Pattern

### Root Cause

Dialogs with inline `StatefulBuilder`, `TextEditingController`, and `setState` caused "Tried to build dirty widgets in the wrong build scope" errors during dismissal. Controllers were used after disposal, and side effects (success toasts, provider reloads) ran while the dialog was still being popped, which conflicted with the active build scope.

### Pattern

Use `AppDialogForm<T>` for every form dialog:

- Put it inside `showDialog<T>`.
- Create `TextEditingController`s with `state.textController(key, text: ...)`. `AppDialogFormState` owns and disposes them when the route is removed.
- Use `state.value<T>(key)` and `state.setValue<T>(key, value)` for non-text state such as toggles, role dropdowns, and selected images.
- Use `state.formKey` for `Form` validation.
- Call `state.markChanged()` on user input so `state.hasChanges` can guard cancellation.
- Save logic sets `state.setSaving(true)`, validates, calls the service, and then `state.pop(const ModalResult<T>.saved(...))` on success. Errors keep the dialog open and call `state.setSaving(false)`.
- Cancel logic pops `const ModalResult<T>.cancelled()`.
- Side effects, toasts, and provider reloads happen **after** `await showDialog` returns in the parent screen, not inside the dialog.
- The parent checks the `ModalResult` and acts: `r?.isSaved`, `r?.isCancelled`, `r?.isFailed`.

### Files Added/Changed

- `lib/ui/widgets/app_dialog_form.dart` — new reusable widget that owns controller lifecycle and dialog state.
- Refactored dialog forms:
  - `lib/ui/screens/products_screen.dart`
  - `lib/ui/screens/categories_screen.dart`
  - `lib/ui/screens/ai_quota_management_page.dart`
  - `lib/ui/screens/staff_detail_screen.dart`
  - `lib/ui/screens/staff_management_screen.dart`
  - `lib/ui/screens/users_screen.dart`
  - `lib/ui/screens/profile_screen.dart`
  - `lib/ui/screens/announcements_screen.dart`
  - `lib/ui/screens/settings/security_settings_page.dart`
  - `lib/ui/screens/settings/pin_settings_page.dart`
  - `lib/ui/screens/settings/store_information_settings_page.dart`

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 232/232 tests.

 
 #   R o l e ,   P e r m i s s i o n ,   G C a s h   Q R ,   N o t i f i c a t i o n ,   a n d   D i a l o g   R e p a i r   N o t e s 
 
 
## Design Decisions

- **Owner owns the business continuity settings.** `_ownerPermissions` now includes `backup_restore`. The previous restriction kept backup/restore off the Owner''s Settings screen; the business owner should control it.
- **Admin stays out of business analytics.** `_systemAdminPermissions` no longer includes `view_reports` or `view_staff_performance`. Admin manages users, AI config, backups, and system settings.
- **Activity logs are per-actor, never global.** `ActivityLogService.getRecentActivities()` returns only the current user''s logs. Owner and Admin see their own actions in the dashboard and on the Activity Logs screen.
- **Trash tabs are permission-driven.** `TrashScreen` builds its tab list from `view_products`, `view_categories`, and `manage_users`, and it gates restore/delete with the matching entity permission.
- **GCash uses a merchant QR stored in settings.** `settings.gcash_qr_image_path` and `settings.gcash_qr_image_type` persist the QR image. `SettingsService` uploads/clears it, `PaymentSettingsPage` previews it, and `GcashPaymentScreen` displays it during checkout.
- **Staff report submissions notify Owners.** `ReportService.submitReport()` creates a `report_submitted` notification for every Owner account.
- **Backup packages include image directories.** `BackupService` now zips `payment_evidence/`, `gcash_qr/`, and `images/` and restores them.
- **`RouteGuard` uses `AccessDeniedScreen`.** Unauthorized navigation now pushes the dedicated screen instead of a generic dialog.

## Verification

- `flutter analyze` -- No issues found.
- `flutter test` -- 235 tests passed.

## GCash QR Owner/Staff Flow Repair

### Root Cause

The GCash QR upload and display flow existed but had three operational gaps:

1. **Staff could see a stale QR.** `paymentSettingsProvider` was a normal `FutureProvider` that cached its value; when the Owner replaced the QR image, the Staff POS did not fetch the new image on the next tender.
2. **QR image was downscaled for scanning.** `AppImage` always resized images to `cacheWidth: 512`, which could blur a dense GCash QR and make it harder to scan.
3. **Admin could reach payment settings in the UI and, via `SettingsService.updateSettings`, change GCash configuration.** The existing `edit_settings` permission is shared by Owner and Admin, and the Owner already has `manage_users` in the current working tree, so `!manage_users` was not a safe differentiator.
4. **No guidance when the QR was missing.** `GcashPaymentScreen` returned an empty `SizedBox` when `gcashQrImagePath` was null, so Staff saw no QR and no explanation.

### Changes Made

- `lib/core/session_manager.dart`
  - Added `canEditBusinessSettings()` which checks **role == UserRole.owner** plus `edit_settings`.
  - This fixes the Owner/Admin boundary even though the Owner permission set now includes `manage_users`.

- `lib/services/settings_service.dart`
  - `updateGcashQrImage()` and `clearGcashQrImage()` now require `canEditBusinessSettings()`.
  - `updateSettings()` now also rejects an **Admin** user from changing any GCash-related field.
  - Added a private `_gcashSettingsDiffer()` helper to detect changes to GCash fields.

- `lib/ui/screens/settings_screen.dart`
  - `Payment Settings` tile is now hidden from non-owners using `SessionManager().canEditBusinessSettings()`.

- `lib/ui/screens/payment_settings_page.dart`
  - `_loadSettings()` gates the page with `canEditBusinessSettings()`.
  - After a successful QR upload or clear, `ref.invalidate(paymentSettingsProvider)` flushes the provider so the Staff POS fetches the fresh QR.

- `lib/ui/screens/pos_screen.dart`
  - `_PaymentDialog` now calls `ref.invalidate(paymentSettingsProvider)` in `initState()` so the tender dialog always starts with fresh payment/GCash settings.

- `lib/ui/screens/gcash_payment_screen.dart`
  - Refactored to `ref.watch(paymentSettingsProvider)` so the screen participates in the provider lifecycle and rebuilds with the latest settings.
  - Added a dedicated missing-QR state (`_buildMissingQrCard`) that explains the situation to Staff and gives the Owner a "Configure GCash QR" button that navigates to `PaymentSettingsPage`.
  - Updated `_buildMerchantQrCard` to render the merchant QR at full resolution (`cacheWidth: null`).

- `lib/ui/widgets/app_image.dart`
  - Added an optional `cacheWidth` parameter that defaults to `512` and can be set to `null` to decode the image at its original size.

- `lib/ui/widgets/app_dialog.dart`
  - Added `showIcon` (default `true`). The payment method dialog uses `showIcon: false` to avoid a generic info icon in a tender context.

- `lib/data/repositories/trash_repository.dart` / `lib/data/repositories/stock_history_repository.dart` / `lib/data/dao/stock_history_dao.dart`
  - Minor signature updates (`where`/`whereArgs` on `TrashRepository.getAll`, `limit` on `StockHistoryRepository.getByUserId`) so the uncommitted trash feature in the working tree continues to compile while the GCash work is verified.

### Verification

```powershell
flutter analyze
flutter test test/gcash_payment_service_test.dart
flutter test test/payment_proof_service_test.dart test/file_type_utils_test.dart
flutter test test/owner_integration_test.dart
flutter test test/session_manager_test.dart
flutter test test/owner_screens_test.dart
```

Results:
- `flutter analyze` -- No issues found.
- `gcash_payment_service_test.dart` -- 9/9 passed.
- `payment_proof_service_test.dart` + `file_type_utils_test.dart` -- 43/43 passed.
- `owner_integration_test.dart` -- 21/21 passed.
- `session_manager_test.dart` -- 3/3 passed.
- `owner_screens_test.dart` -- 14/14 passed.

### QA Notes

- Staff POS tender flow: when the Owner replaces the GCash QR in Payment Settings, the next `_PaymentDialog` + `GcashPaymentScreen` will load the new image.
- QR image is no longer downscaled (`cacheWidth: null`) for the merchant QR in both `PaymentSettingsPage` and `GcashPaymentScreen`.
- Payment Settings and GCash QR management are Owner-only. Admin still has `edit_settings` for AI/system settings but cannot reach or mutate GCash payment configuration.

## Trash/Attachment/Permission Refactor

### Root Cause

The trash feature had several architectural gaps:

1. `TrashService` and the `trash` table were largely unused. Soft deletion was duplicated in `ProductService`, `CategoryService`, and `UserService`, so the Trash UI read from source-table `getDeleted()` methods and the dashboard trash count was wrong.
2. There was no central authority for restore or permanent delete, so attachment cleanup and permission checks were inconsistent.
3. `SessionManager` did not give the Owner `manage_users`/`delete_users`/`view_users`/`empty_trash`, and the Admin lacked `view_users`, which conflicted with the intended role/permission matrix.
4. `TrashScreen` read from separate product/category/user providers and used `manage_users` to gate the Users tab.
5. Product/user images were not tracked as attachments, so permanent deletion could leave orphaned files and backup/restore did not include the new `attachments/` directory.

### Changes Made

- `lib/core/session_manager.dart`
  - Added `manage_users`, `edit_users`, `delete_users`, `reset_password`, `toggle_user_active`, `view_users`, and `empty_trash` to Owner.
  - Added `view_users` to Admin.

- `lib/services/trash_service.dart`
  - Rewrote `moveToTrash`, `restoreByEntity`, `restoreFromTrash`, `permanentDelete`, and `emptyTrash` to be the single authority for soft-delete/restore/permanent-delete.
  - Uses database transactions, snapshots JSON for each trashed entity, attachment lifecycle management, and `TrashOperationResult` for consistent feedback.
  - Added `snapshotForProduct`, `snapshotForCategory`, and `snapshotForUser` helpers.

- `lib/services/product_service.dart`, `lib/services/category_service.dart`, `lib/services/user_service.dart`, `lib/services/staff_service.dart`
  - Soft delete, restore, and permanent delete now route through `TrashService`.
  - `ProductService` and `UserService` record primary profile/product images as attachments via `AttachmentService`.

- `lib/services/attachment_service.dart`, `lib/services/file_storage_service.dart`, `lib/data/dao/attachment_dao.dart`, `lib/data/repositories/attachment_repository.dart`, `lib/data/models/attachment.dart`
  - Generic attachment lifecycle: add, soft-delete, restore, permanently delete, and replace primary images.
  - `FileStorageService` added `getFileSize` for trash metadata.

- `lib/core/database.dart`
  - Bumped schema to version 20.
  - Added `attachments` table and indexes.
  - Extended `trash` with `snapshot_json`, `attachment_count`, and `total_size_bytes`.

- `lib/data/models/trash_item.dart`
  - Added `attachmentCount` and `totalSizeBytes` fields and JSON accessors.

- `lib/ui/screens/trash_screen.dart`
  - Rewritten to read from `trashServiceProvider` and display `TrashItem` records.
  - Tabs are gated by `view_products`, `view_categories`, and `view_users`.
  - Restore uses `restore_trash` + the view permission for the tab; permanent delete uses the type-specific delete permission.
  - Added search/filter across entity names and snapshots, and an `empty_trash` button.

- `lib/services/backup_service.dart`
  - Backup packages now include the `attachments/` directory and restore it.

### Verification

```powershell
flutter analyze
flutter test --concurrency=1 test/owner_integration_test.dart
flutter test --concurrency=1 test/user_service_test.dart
flutter test --concurrency=1 test/staff_service_test.dart
flutter test --concurrency=1 test/owner_screens_test.dart
```

Results:
- `flutter analyze` -- No issues found.
- `owner_integration_test.dart` -- 24/24 passed.
- `user_service_test.dart` -- 21/21 passed.
- `staff_service_test.dart` -- 17/17 passed.
- `owner_screens_test.dart` -- 14/14 passed.

A full `flutter test` also passes 239/239 with `--concurrency=1` on Windows to avoid the `sqflite_common_ffi` file-lock race.

## Android Backup `createDocument` Invalid URI Fix

### Root Cause

`MainActivity.createDocument()` passed the raw tree URI returned by `ACTION_OPEN_DOCUMENT_TREE` straight to `DocumentsContract.createDocument()`. `DocumentsContract.createDocument()` expects a **document** URI, not a **tree** URI, so some Android builds and document providers threw `IllegalArgumentException: Invalid URI` at `ContentResolver.call(... DocumentsContract.java:1380)` and the backup failed before any file was written.

### Changes Made

- `android/app/src/main/kotlin/com/pinoypos/pinoy_pos/MainActivity.kt`
  - `createDocument()` now checks `DocumentsContract.isTreeUri(treeUri)` and early-returns `INVALID_ARGS` when the saved location is not a tree.
  - It converts the tree URI to a document URI with `DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri))` before calling `DocumentsContract.createDocument()`.

### Verification

```powershell
flutter analyze
flutter build apk --debug
```

Results:
- `flutter analyze` -- No issues found.
- `flutter build apk --debug` -- Built successfully.

## Global Input Field Design System

### Pattern

All data-entry fields use the shared components in `lib/ui/widgets/app_input_fields.dart`:

- `AppTextFormField` — general labeled/hinted text or number input (supports label, hint, helperText, prefixIcon/prefix/prefixText, suffixIcon/suffix/suffixText, keyboardType, validators, obscureText, etc.).
- `AppPasswordField` — any password/PIN-style secret input; owns the visibility-toggle suffix icon and supports `isLoading` to disable it.
- `AppDropdownField<T>` — dropdowns that match the text-field design (same filled surface, radius, border, icon colors).
- `AppSearchField` — compact search bars with a leading search icon and optional `onClear` button.

### Visual source of truth

`InputDecorationTheme` in `lib/core/app_theme.dart` owns the look: filled surface (`surfaceContainerLow` light / `surfaceContainerHighest` dark), 16px radius, subtle `outlineVariant` border, 1.5px `primary` focus ring, `error` error borders, state-aware label/icon colors, and `contentPadding` 16x16. `textSelectionTheme` sets the primary cursor/selection.

### Rules

- Never set `border:`/`enabledBorder:`/`focusedBorder:`/`errorBorder:`/`borderRadius` inside `InputDecoration` at call sites — the theme owns them.
- Do not re-implement password visibility toggles; use `AppPasswordField`.
- Specialized fields that keep a custom widget (AI chat composers, imperative `errorText` fields like the SuperAdmin password) must still omit explicit border overrides so the theme applies.
- Icon colors come from `prefixIconColor`/`suffixIconColor` theme states; only pass a fully styled `prefix`/`suffix` widget when the default state colors are not appropriate (e.g., login's always-primary icons).

### Verification

```powershell
flutter analyze
flutter test test/app_input_fields_test.dart
```
