# Pinoy POS Agent Notes

## Responsive CRUD Action Placement

### Rule

The primary Add/Create action for a CRUD module lives in exactly one place
per layout:

- **Compact width + portrait** → `FloatingActionButton` (extended at >=360
  logical px, circular below).
- **Every other layout** (compact landscape, tablet, desktop, resized
  windows) → labeled `AppButton` inside the screen's `CrudToolbar`.
- **`AppHeader` never hosts a module create action.** It keeps title,
  back, theme toggle, notification bell, and profile menu only.

### API (`lib/ui/widgets/responsive_create_action.dart`)

- `ResponsiveCreateAction(label, icon, onPressed, tooltip?, color?)`
  - `isFabLayout(context)` — true only for compact width AND portrait.
  - `contentAction(context)` — toolbar button, `null` on FAB layouts.
  - `fab(context)` — FAB, `null` on non-FAB layouts. Per-label `heroTag`.
    `color` defaults to `AppButtonColor.primary`; other roles resolve to
    semantic background/foreground pairs (e.g. `warning` for Reset All).
  - `contentBottomClearance(context)` — `fabClearance` (88) on FAB layouts,
    else 0. Add it to scrollable list bottom padding so the last item
    clears the FAB.
  - Permission gating stays at the call site: construct the object only
    when `hasPermission(...)` allows it.
- `CrudToolbar(search?, controls, pinnedControls, primaryAction, padding, maxSearchWidth)`
  - Compact: search stacked above a horizontally scrollable controls row
    with pinned controls and the primary action pinned right.
  - Medium+: single row — capped search (`Flexible` + `ConstrainedBox`),
    scrollable `controls` in `Expanded`, `pinnedControls` and
    `primaryAction` trailing.

### Screens migrated

- `products_screen.dart` — toolbar: search + category dropdown + Add Product.
- `categories_screen.dart` — toolbar: search + status chips + Add Category;
  a lone action row renders when the list is empty so the action stays
  reachable. Refresh stays in the header as a secondary icon.
- `users_screen.dart` — toolbar: search + pinned refresh + Add User; role
  chips remain on their own row.
- `staff_management_screen.dart` — toolbar: search + filter chips +
  pinned sort menu + Add Staff.
- `stock_screen.dart` — toolbar: search + stock chips + divider +
  category chips + Add Stock.
- `report_submissions_screen.dart` — owner-only toolbar: Import.
- `announcements_screen.dart` — toolbar: pinned refresh + Add Announcement.
- `ai_quota_management_page.dart` — Reset All Usage uses the same
  component (warning color); FAB only on compact portrait, content button
  next to "Change Default Quota" otherwise.

### Verification

```powershell
flutter analyze
flutter test test/responsive_create_action_test.dart
```

`flutter analyze` reports no issues; the new widget tests cover FAB on
compact portrait, circular FAB below 360px, in-content button on compact
landscape/tablet/desktop, single-action exclusivity, and FAB clearance.

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

## Role Dashboard Audit and Repair Pass

### Design Decisions

- **Admin dashboard is system/maintenance only.** Admin never had `view_reports`, so the sales-analytics sections in `_AdminDashboard` were dead code. They were removed rather than granting Admin business analytics.
- **Activity logs stay self-scoped for every role.** `ActivityLogService.getRecentActivities` returns only the current user's actions. No system-wide audit view was added.
- **Announcements reach Staff through notifications only.** Staff still lack `view_announcements`; the announcement body is now included in the notification message (`New Announcement: <title>`) because the notification is their only way to read it.

### Changes Made

- `lib/services/announcement_service.dart`
  - Staff announcement notifications now carry the full announcement content, not just the title.

- `lib/services/dashboard_service.dart`
  - Added `sealed class DashboardData`; `OwnerDashboardData`, `AdminDashboardData`, and `StaffDashboardData` are its subtypes. `getDashboard` returns `Future<DashboardData?>`, so the UI switches on the payload type instead of the live session role (removes the `owner!`/`admin!`/`staff!` crash risk on mid-load account changes).
  - `AdminDashboardData` dropped the nullable `analytics` field and gained `exportCount`, `lastExportAt`, `aiConfigured`, `aiModel`, and `aiQueriesToday`.
  - `getAdminDashboard` no longer fetches sales analytics; it loads export-history summary, Groq configuration status (best-effort — secure storage can throw on platforms without a keychain), and today's AI query usage across active users.

- `lib/providers/dashboard_provider.dart`
  - Added `DashboardDenied` state so an authenticated user without `view_dashboard` sees an access-denied view instead of "Not authenticated".
  - `DashboardLoaded` now carries a single `DashboardData data` field.
  - `DashboardNotifier` takes `isAuthenticated`; the provider watches `authStateProvider.select((s) => s.user != null)` so the dashboard reloads on login/logout/account switch.

- `lib/ui/screens/dashboard_screen.dart`
  - Removed the unreachable sales-analytics sections and helpers from `_AdminDashboard` (~180 lines of dead code).
  - `PeriodSelector` is hidden for Admin (no admin metric is period-driven).
  - Added `_DashboardDeniedView` for the denied state.
  - Added Admin "Export History" and "AI Service" cards plus an "AI Config" quick action.
  - All dashboard quick actions now route through `RouteGuard.pushIfAuthorized` for consistent permission checks and denied-attempt logging.

- Tests
  - `test/analytics_dashboard_test.dart` — added "Admin dashboard returns system metrics only".

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 269/269 tests.

## Dialog / Keyboard Responsiveness Pass

### Verification

```powershell
flutter analyze
flutter test --concurrency=1
```

## Global Color and Radius System

### Source of truth

`lib/core/app_theme.dart` now contains:

- `AppColorTokens` — the exact requested foundation palette (`primaryBlue`, `darkBackground`, `darkSurface`, `lightBackground`, `textPrimary`, etc.).
- `AppSemanticColors` — primary, success, warning, error, info, neutral, disabled roles plus theme-aware `resolve`/`resolveSurface`/`contrastFor` helpers.
- `AppColors` — `ColorScheme` built directly from those tokens for both light and dark, with component themes for cards, buttons, inputs, dialog, navigation, FAB, chips, list tiles.
- `AppRadius` — `xs`, `sm`, `md`, `lg`, `xl`, `xxl` plus semantic aliases (`chip`, `control`, `input`, `card`, `dialog`, `fab`, `menu`).

### Theme rules enforced

- No `Color(0x...)` values outside `app_theme.dart`.
- No `Colors.white`/`Colors.black`/`Colors.blue`/`Colors.red`/`Colors.green`/`Colors.orange` in UI code; `Colors.transparent` is still allowed for see-through surfaces.
- No hardcoded `BorderRadius.circular(N)` or `Radius.circular(N)` values in `lib/ui` or `lib/core`; all rounding uses `AppRadius`.
- `main.dart` already consumes `AppColors.getLightTheme()` / `AppColors.getDarkTheme()`.
- `quick_action_theme.dart` now only uses the semantic `primary/success/info/warning/neutral` families.
- `app_button.dart`, `app_card.dart`, `app_input_fields.dart`, `app_dialog.dart`, `notification_bell.dart`, `profile_menu.dart`, `app_status_chip.dart`, and all audited screens now consume the tokens.

### Verification

```powershell
flutter analyze
flutter test test/app_button_theme_test.dart
flutter test test/owner_screens_test.dart test/app_input_fields_test.dart
flutter test test/payment_qr_service_test.dart test/payment_settings_page_test.dart test/trash_qr_test.dart
flutter test
```

Result (most recent run): `flutter analyze` reports no issues; `flutter test` passes 383/383 tests.

Recommended: run the full suite with `--concurrency=1` on Windows if `sqflite_common_ffi` file-lock races appear.

Result: `flutter analyze` reports no issues. The full test suite passes 305/305 tests when run with `--concurrency=1` on Windows. The default parallel runner can hit `database is locked` errors in the integration tests because multiple test suites share the same `sqflite_common_ffi` database file on disk. Use `--concurrency=1` for a clean full run; targeted widget and unit tests run cleanly without it.

## POS Payment Riverpod Crash + At-Till GCash Verification

### Root Cause

`_PaymentDialogState.initState()` called `ref.invalidate(paymentSettingsProvider)`. In flutter_riverpod 2.6.x, `ref.invalidate` on a `ConsumerState` resolves the lazy `ConsumerStatefulElement._container` via `ProviderScope.containerOf(context)` with `listen: true`, which calls `dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>()`. Inherited-widget dependency registration is illegal before `initState()` completes, so the dialog crashed on open. `ref.read`/`ref.refresh` are safe in `initState` because they resolve the container with `listen: false`.

Separately, the GCash verification model was inconsistent:

1. `gcash_verification_mode != immediate` marked **every** GCash sale `pending`, including the Owner's own sales, forcing the Owner to self-verify.
2. The `admin` and `owner_admin` modes were dead configuration: the System Admin lacked `verify_payments` (and has no `view_sales`/POS access), so only an Owner could ever confirm a pending sale.
3. The payment-settings dropdown conflated "who must verify" with "who can verify".

### Changes Made

- `lib/ui/screens/pos_screen.dart`
  - Removed `ref.invalidate` from `_PaymentDialogState.initState()`.
  - `_checkout()` now invalidates `paymentSettingsProvider` in the event handler before `showDialog`, preserving "fresh settings on each open" without a lifecycle violation.

- `lib/services/payment_verification_service.dart` (new)
  - Single authority for the verification policy. Distinguishes **operator** (the logged-in user tendering the sale) from **verifier** (who may approve).
  - `requiresVerificationFor(operatorRole, paymentMethod, settings)`: GCash only; `UserRole.owner` is always exempt; other operators require verification only when the policy is enabled.
  - `canRoleVerify(role, settings)`: Owner always verifies; System Admin verifies when `adminCanVerify`.
  - `authenticateVerifier(username, password, settings)`: validates a verifier's own credentials **without** changing the session (at-till approval). Generic "incorrect username or password" for credential failures; explicit "not authorized" for valid credentials with the wrong role; self-verification is rejected.

- `lib/ui/dialogs/gcash_verification_dialog.dart` (new)
  - `showGcashVerificationDialog` uses `AppDialogForm` + `ModalResult<User>`; shows amount, operator, and method; collects verifier username/password; cancel/dismiss returns cancelled so the caller aborts without touching the cart.

- `lib/services/sales_service.dart`
  - `createSale` accepts `verifiedByUserId`. When the operator requires verification, a missing or unauthorized verifier throws `PaymentValidationException` **before** the sale is inserted — no pending row, no stock deduction, cart preserved. On success the sale is `confirmed` with `verified_at`/`verified_by` set.
  - New sales are never created as `pending`; `getPendingPayments`/`confirmGcashPayment`/`rejectGcashPayment` remain for legacy pending rows.
  - `_canVerify` delegates to `PaymentVerificationService.currentUserCanVerify`.

- `lib/data/models/payment_settings.dart`
  - Removed `requiresOwnerVerification`/`requiresAdminVerification`; added `adminCanVerify` (legacy `admin` is treated as `owner_admin`).

- `lib/core/session_manager.dart`
  - `_systemAdminPermissions` now includes `verify_payments` so the Admin can act as an at-till verifier when the policy allows. Admin still cannot view sales.

- `lib/ui/screens/gcash_payment_screen.dart`
  - `_completeSale` runs the verification gate before `createSale`; a cancelled dialog returns to the review step with cart/proof intact.
  - The review banner now reflects the actual policy for the current operator and names the authorized verifier roles.

- `lib/ui/screens/payment_settings_page.dart`
  - Replaced the four-option dropdown with a "Verify staff GCash sales" toggle plus a "Who can verify" dropdown (`Owner only` / `Owner or System Admin`). This is the single authoritative verification policy; the Owner never appears as someone who must verify their own sale.

- `lib/core/database.dart` / `lib/core/constants.dart`
  - Database version bumped to 22. v22 migration normalizes `gcash_verification_mode = 'admin'` to `'owner_admin'`. Valid stored values: `immediate`, `owner`, `owner_admin`.

- `test/gcash_payment_service_test.dart`
  - New coverage: owner exemption, staff-requires-verifier (throws, no sale, no stock movement), staff+verifier confirmed, unauthorized/owner-only verifier rejection, `authenticateVerifier` accept/reject matrix.
  - Legacy pending confirm/reject tests now seed pending rows directly via `SaleRepository`/`SaleItemRepository` since `createSale` no longer creates pending sales.

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 312/312 tests.

### Flow Summary

```text
OWNER
POS → GCash → Confirm → DONE (no verification)

STAFF
POS → GCash → Verify (Owner/Admin credentials) → APPROVED → DONE
                                    ↓
                            REJECT/CANCEL → NO SALE, CART REMAINS
```


## Dynamic Session Timeout & Expiry Warning

### What Was Already in Place

- `SessionTimeoutService` is the single timer authority: one inactivity timer and one absolute-expiry timer, both computed from wall-clock timestamps (`lastActivityAt`, `sessionExpiresAt` from persisted `SessionMetadata`). Lifecycle pause persists `lastActivityAt` and cancels timers; resume recomputes from the wall clock.
- `SessionGuard` (root widget in `MaterialApp.builder`) captures global pointer + keyboard input and auth changes via `ref.listenManual`.
- `settings.inactivity_timeout_minutes` (v21) is editable in Settings > Security; Admin and Owner both hold `edit_settings`. A per-user override (`users.inactivity_timeout_minutes`) wins over the store default.

### Changes Made

- `lib/services/session_timeout_service.dart`
  - Added a warning phase between "idle" and "expired": the inactivity timer now fires at `timeout - warningThreshold`, enters the warning window (`onWarning` callback), and arms a final countdown timer that fires `onInactivityTimeout` at the absolute deadline.
  - `userDidInteract` is ignored while the warning is active — the countdown requires an explicit choice; stray taps/keys do not silently extend the session.
  - `continueSession()` clears the warning, resets the inactivity clock to the full configured timeout, and persists the new activity timestamp.
  - `isWarningActive` / `inactivityDeadlineAt` exposed for the UI.
  - All timers cancelled together; `endSession` and lifecycle pause clear the warning flag.

- `lib/services/session_settings_service.dart`
  - `getWarningThreshold()` reads `settings.session_warning_seconds` (default 30).
  - `getEffectiveWarningThreshold(user)` clamps the warning below the effective inactivity timeout (a warning can never be >= the timeout; returns zero when there is no room).

- `lib/data/models/settings.dart` / `lib/core/database.dart` / `lib/core/constants.dart`
  - New `session_warning_seconds INTEGER NOT NULL DEFAULT 30` column (v23 migration, try/catch idempotent; also added to the `settings` CREATE TABLE). `databaseVersion` bumped to 23.
  - `Settings.sessionWarningSeconds` (default 30) plumbed through `toMap`/`fromMap`/`copyWith`.

- `lib/ui/widgets/app_countdown_ring.dart` (new)
  - Reusable circular countdown indicator: full-track + remaining-arc
    `CircularProgressIndicator` pair with a centered label, warning-semantic
    color, theme-aware track. Pure view — owns no timer; callers pass the
    remaining fraction (0.0–1.0).

- `lib/ui/dialogs/session_expiring_dialog.dart` (new)
  - "Session Expiring" modal on the existing `AppDialog` design (warning type, non-dismissible, no close button).
  - A single 250 ms ticker recomputes the remaining time from the absolute deadline; the same value drives both the centered number (ceil to whole seconds, singular/plural label) and the `AppCountdownRing` arc (remaining / warning-window fraction). Suspend/resume safe.
  - `Semantics` live region, "Continue Session" (primary) and "Log Out" (destructive) actions. `clock` is injectable for tests.

- `lib/ui/widgets/session_guard.dart`
  - `onWarning` pushes a `DialogRoute` directly on `navigatorKey.currentState` (the guard sits *above* the root navigator, so `Navigator.of` cannot reach it).
  - The route is tracked in `_warningRoute` so the dialog can never be shown twice; it self-pops via its buttons or when the countdown reaches zero, and any auth-phase `pushAndRemoveUntil` removes it with the rest of the stack.
  - "Log Out" performs a full logout (not a PIN lock) through the existing `_pushAuthPhaseAndUpdate`/`logout()` path; "Continue Session" calls `continueSession()`.

- `lib/ui/screens/settings/security_settings_page.dart`
  - New "Session warning" tile + edit dialog (seconds, validated >= 5 and < the inactivity timeout), same `edit_settings` gate as the timeout tile.

- `test/session_timeout_service_test.dart`
  - `_FakeSessionSettingsService` accepts a `warning` duration; all constructors updated for the new `onWarning` callback.
  - New tests: warning fires at threshold then timeout at deadline; activity during warning does not reset; `continueSession` restores the full timeout; zero threshold skips the warning phase.

- `test/session_expiring_dialog_test.dart` (new)
  - Widget tests for the warning modal: full/half ring fractions, singular "1 second" label, Continue/Log Out dismissal + callbacks (deterministic via the injected `clock`).

### Behaviour

- Timeout and warning are configured per store (`settings`) with optional per-user timeout override; changes apply to new sessions and the next timer restart.
- Activity = global pointer + keyboard input; navigation/scrolls count; provider rebuilds do not.
- Warning appears at the configured threshold (default 30s) before expiry; countdown is absolute-time based.
- Manual logout, PIN lock, and the 8-hour absolute lifetime are unchanged.

### Verification

```powershell
flutter analyze
flutter test
```

Result: `flutter analyze` reports no issues; `flutter test` passes 321/321 tests (11/11 in `session_timeout_service_test.dart`, 5/5 in `session_expiring_dialog_test.dart`).


## POS Mobile/Portrait UX Pass

### What Changed

- lib/ui/screens/pos_screen.dart
  - Two-pane POS layout now engages at >= 840 px (_twoPaneMinWidth) instead of the generic 600 px medium breakpoint, so portrait tablets keep the stacked phone layout and the product pane never shrinks below ~500 px beside the cart.
  - _CartItemRow shows a fixed 56 px AppImage thumbnail (Icons.inventory_2_outlined fallback, cacheWidth: 128) and splits content into a name/remove row and a quantity/subtotal row, so long names ellipsize instead of pushing controls off screen.
  - Compact layout replaces the floating cart FAB with _MobileCartBar, a sticky bottom bar (item count + total + Checkout) inside the layout's SafeArea; tapping the summary opens the editable cart sheet, Checkout jumps straight to the payment dialog.
  - _buildProductGrid derives column count from the grid's own LayoutBuilder width (min tile 150 px compact / 170 px wide, clamped 2-4 / 2-6 columns).
  - The wide-layout cart panel width scales with the window via (width * 0.34).clamp(320, 420).
  - _CheckoutPanel accepts the DraggableScrollableSheet scroll controller so the cart list drives the drag gesture in the bottom sheet.
  - The payment dialog's method dropdown is replaced by _PaymentMethodTile tiles (icon + label, 56 px min height, theme colors) in a 2-column wrap on compact widths and a single row when there is room; the pos_payment_method key is kept on the selector.
- lib/ui/screens/gcash_payment_screen.dart
  - _buildOrderSummary card (cart items, capped at 3 rows + "+N more") now sits at the top of both the details and review steps.
  - _buildTotalCard uses cs.primaryContainer, fixing onPrimaryContainer text on a default surface (contrast bug in dark mode).
  - _buildProofThumbnail uses AppImage so missing/corrupted proof files show a themed placeholder instead of a bare Icons.broken_image.
- lib/ui/screens/payment_success_screen.dart
  - The summary card scrolls inside Expanded so the action buttons stay reachable on short screens.

### Unchanged Behaviour

- Cart add/increment/decrement/remove, stock validation, checkout permissions, payment Required/Optional settings, GCash verification flow, inventory deduction, sale persistence, and receipt/success navigation are untouched.
- Sales screen was already card-based (AppListItem) with responsive PeriodSelector (stacks under 360 px); sale detail and receipt screens already use Expanded/Flexible rows with 600-800 px max-width constraints.

### Verification

`powershell
flutter analyze
flutter test test/owner_screens_test.dart test/cart_provider_test.dart test/payment_pos_validation_test.dart test/gcash_payment_service_test.dart test/payment_settings_page_test.dart test/app_dialog_form_test.dart test/app_input_fields_test.dart test/app_button_theme_test.dart test/period_selector_test.dart test/sales_period_selector_test.dart test/sales_trend_chart_empty_test.dart test/dialog_dismiss_test.dart test/modal_result_test.dart
`

Result: lutter analyze clean on changed files (one pre-existing info-level lint in 	est/trash_unified_test.dart, unrelated). Focused suites pass 112/112. The full lutter test run could not complete in this environment because concurrent lutter invocations lock uild/native_assets/windows/sqlite3.dll and kill the run; all POS/payment/widget suites were verified individually.


## Date-Sequential Receipt Numbers (YYYYMMDD-NNNN)

### What Changed

- lib/core/security.dart
  - Removed SecurityHelper.generateReceiptNumber() (timestamp + random RCP� values). SaleRepository.nextReceiptNumber is now the single authoritative generator.
- lib/data/dao/sale_dao.dart
  - getMaxReceiptSequence(datePrefix, {txn}) returns MAX(CAST(substr(receipt_number, 10) AS INTEGER)) for rows matching 'YYYYMMDD-%'. All rows count (confirmed, voided, cancelled, soft-deleted) so consumed numbers are never reused; legacy RCP� rows never match the prefix.
- lib/data/repositories/sale_repository.dart
  - 
extReceiptNumber(businessDate, {txn}) formats YYYYMMDD-NNNN using the **local** business date (
eceiptDatePrefix uses 	oLocal()), zero-padded to 4 digits.
- lib/services/sales_service.dart
  - createSale generates the receipt number inside the existing SQLite transaction, sharing one DateTime.now() for createdAt and the receipt prefix.
  - The insert retries up to 3 times on DatabaseException.isUniqueConstraintError() (the 
eceipt_number TEXT UNIQUE column is the final duplicate guard); on conflict it re-reads the table and takes the next free sequence rather than failing.
- 	est/receipt_number_test.dart (new, 12 tests)
  - Format YYYYMMDD-0001 first sale, same-day increment, regex format, continuation from persisted rows, next-day reset to 0001, legacy RCP� rows ignored, createSale skipping a taken number, voided-sale numbers not reused, search by full/date/sequence, created_at ordering, and failed-sale lifecycle (no number consumed).

### Unchanged

- No schema migration needed: 
eceipt_number TEXT UNIQUE already exists; historical RCP� numbers are preserved and cannot collide with the new format.
- All UI surfaces already render sale.receiptNumber (sales list 'Sale #', transaction list, sale detail, receipt screen/PDF, dashboard, reports export, AI navigation), so the new format flows through without display changes.
- Search already covers 
eceipt_number LIKE in getFilteredSales/getConfirmedSalesForRange, so 20260908, 20260908-0007, and  007 all match.
- Ordering stays created_at DESC, which aligns with the per-day sequence.

### Verification

`powershell
flutter analyze
flutter test test/receipt_number_test.dart test/gcash_payment_service_test.dart test/payment_pos_validation_test.dart test/sales_screen_responsive_test.dart test/owner_integration_test.dart test/owner_screens_test.dart
`

Result: lutter analyze clean on changed files; 12/12 new tests pass and all sales/payment regression suites pass.

## GCash Payment Screen Audit, QR Payload Decoding, and Mobile-First Redesign

### Audit Findings

- `GcashPaymentScreen` already split compact/wide via `layoutClassFor`, scrolled safely, and enforced settings-driven validation, but `PaymentQrService` only detected QR bounds for cropping — the payload was never decoded.
- The QR was capped at 220 px on phones and merchant identity came only from manually configured `storeName`/`storePhone`; nothing distinguished QR-decoded data from configured data.
- No QR-amount vs POS-total handling existed.

### Changes Made

- `lib/data/models/decoded_payment_qr.dart` (new)
  - `DecodedPaymentQr` model: `rawPayload`, `status` (`notDetected` / `unreadable` / `decodedUnparsed` / `recognized`), `detectionSource`, `paymentNetwork`, `merchantName`, `merchantCity`, `countryCode`, `currencyCode`, `amount`, `accountIdentifier`, `mobileNumber`, `qrReference`, `isStatic`, `crcValid`. Missing fields stay null — nothing is fabricated.

- `lib/services/payment_qr_parser.dart` (new)
  - Pure-Dart EMVCo MPM TLV parser (the standard behind QR Ph / GCash / InstaPay codes).
  - Extracts payload format, point of initiation (static/dynamic), merchant account templates (tags 02-51), MCC, currency (608 → PHP), amount, country, merchant name (59), city (60), additional-data mobile (62.02) and QR-carried reference (62.01/62.05).
  - PH mobile numbers are only reported when a field actually encodes one (masked values like `955241****` are normalized to `+63 955 241 ****`); unrelated values are never converted into a mobile number.
  - CRC-16/CCITT-FALSE is verified when present and reported as `crcValid` without discarding parsed fields.

- `lib/services/payment_qr_service.dart`
  - New `decodePaymentQr(relativePath)`: ZXing `QRCodeMultiReader` results now expose payload `text` (bounds logic unchanged); falls back to `qr_code_dart_decoder`, then feeds the payload through `PaymentQrParser`.
  - Pipeline: QR image → decoder → raw payload → EMVCo parser → `DecodedPaymentQr` → UI state.

- `lib/providers/service_providers.dart` / `lib/providers/payment_settings_provider.dart`
  - `paymentQrServiceProvider` and `paymentQrDecodeProvider` (family keyed by image path, cached per path).

- `lib/ui/screens/gcash_payment_screen.dart`
  - Portrait hierarchy: Total Due → Scan to Pay QR card → Payment Details → Customer/Payment info → Order Summary → Review Payment → secure note.
  - QR sized at 78% of available width clamped to 220-320 px (was 55% capped at 220 px), centered, `BoxFit.contain`, full-resolution decode, tap-to-enlarge into the existing pinch/zoom `AppPaymentQrViewer`.
  - Live decode-status chip in the QR card header: `Reading QR…` (non-blocking spinner), `Merchant details detected`, `Payment QR recognized`, `QR detected — details unavailable`, `Unable to read QR code`.
  - New `Payment Details` card shows only fields that exist: Merchant, Mobile, Account, Network, Amount in QR, QR Reference, marked `Detected from QR` when payload-derived. Configured `storeName`/`storePhone` remain as fallback when the QR encodes nothing.
  - QR-encoded amount is compared against the POS total; a mismatch shows a warning banner while the POS total stays authoritative.
  - Wide layout restructured: QR + configure action on the left; amount, payment details, inputs, order summary and primary action on the right.
  - Customer name is deliberately NOT auto-filled from the QR: the merchant QR identifies the payee, not the customer (documented in `_buildCustomerInfoSection`). Required/optional validation from Payment Settings is unchanged.
  - GCash reference field stays a separate post-payment input; QR-carried references are shown only as `QR Reference`.

### Verification

```powershell
flutter analyze lib\ui\screens\gcash_payment_screen.dart lib\services\payment_qr_service.dart lib\services\payment_qr_parser.dart lib\data\models\decoded_payment_qr.dart lib\providers\payment_settings_provider.dart lib\providers\service_providers.dart
flutter test test/payment_qr_parser_test.dart test/payment_qr_service_test.dart
```

Results:
- Scoped `flutter analyze` — No issues found.
- `payment_qr_parser_test.dart` — 10/10 passed (QR Ph payload, dynamic amount, CRC pass/fail, non-payment payloads, no-fabrication, masked mobile normalization).
- `payment_qr_service_test.dart` — 11/11 passed, including an end-to-end decode of a generated EMVCo QR image.

### Environment Notes (pre-existing, unrelated)

- `flutter analyze` on the whole project reports 4 errors from the in-progress `responsive-crud-actions` refactor (`ResponsiveCreateAction.appBarAction` missing; `AppColorTokens.primaryBlueDark` renamed away) in files this task did not touch.
- DB-backed integration tests (`gcash_payment_service_test.dart`, `user_service_test.dart`) fail in this session with `database is locked` because another `flutter run`/test process holds `.dart_tool\sqflite_common_ffi\databases\pinoy_pos.db`; they fail identically on code paths this task did not modify.

## Reports Role Separation + Sales Import/Export + Announcement Icons

### Business rule enforced

- **Staff** author and submit reports ("My Reports" -> submit to Owner).
- **Owner** reviews staff submissions ("Submitted Reports") and manages sales data directly ("Sales" -> Import/Export). The Owner is never a report author/submitter.

### Changes

- `lib/core/session_manager.dart`
  - Added `submit_reports` (Staff only) and `import_sales` (Owner only).

- `lib/services/report_service.dart`
  - `submitReport` now requires `submit_reports` and `createdBy == currentUser.id`.
  - `getMyReports` returns `[]` for non-author roles (Owner/Admin).
  - `importReport` requires `submit_reports` — importing a report file creates an `export_history` record authored by the current user, so it is staff-only.

- `lib/services/report_export_service.dart`
  - `submitSalesReport` returns `null` early without `submit_reports` (service-layer guard, not just UI).
  - `exportSalesReport` still records an `export_history` `generated` row — that table doubles as the export audit log (used by the admin dashboard export count); those rows never surface as "My Reports" or staff submissions.

- `lib/ui/screens/more_screen.dart`
  - "My Reports" entry gated on `submit_reports` (staff-only). "Submitted Reports" remains `view_report_submissions` (owner-only).

- `lib/ui/screens/report_submissions_screen.dart`
  - `submissionsOnly: true` = Owner inbox (title "Submitted Reports"); `false` = Staff history ("My Reports").
  - Access-denied empty state when the viewer lacks the required permission.
  - The "Import Report" action only exists on the staff "My Reports" view.
  - Owner cards show "Staff: <name>"; staff cards show the report number.
  - `markReportViewed` only runs in the owner inbox.

- `lib/ui/screens/sales_analytics_screen.dart`
  - "Submit to Owner" in the export sheet is gated on `submit_reports` instead of a role check.

- `lib/services/sales_import_service.dart` (new) + `salesImportServiceProvider`
  - `previewSalesImport(fileName, bytes)` parses/validates CSV (required columns: `date`, `total`; optional: `payment_method`, `payment_status`, `cash_received`, `customer`, `reference`, `receipt_number`, `notes`).
  - `importSales(preview)` inserts valid rows inside a transaction, generates `YYYYMMDD-NNNN` receipt numbers when absent, skips duplicate receipt numbers (UNIQUE conflict), and logs `import_sales` to the activity log.
  - Throws `AuthorizationException('import_sales')` for non-owners. No `export_history` writes — imports never create report records.

- `lib/services/sales_analytics_service.dart`
  - `getAnalyticsForBounds` accepts optional `paymentMethod`/`paymentStatus` so the Sales screen exports exactly the filtered slice it shows.

- `lib/ui/screens/sales_screen.dart`
  - Added Export (`export_reports`, PDF/Excel/CSV via `ReportExportService`) and Import (`import_sales`, CSV pick -> validate -> preview -> confirm) actions to the toolbar.

- `lib/ui/screens/announcements_screen.dart`
  - Create action icon changed to `Icons.add`; card actions converted to `AppIconButton` (48px touch targets, tooltips): view (`Icons.visibility_outlined` -> read-only `AppDialog`), pin (`selected` state), edit (`Icons.edit_outlined`), delete (`Icons.delete_outline` with `cs.error`). Card tap also opens the view dialog.

### Verification

- `dart analyze lib test` — no issues.
- `flutter test` — 433 tests pass (97 in the reports/sales/RBAC batch + 336 remainder), including 12 new tests in `test/report_workflow_test.dart` covering owner-submission denial, staff submit->owner inbox, More-entry filtering, CSV preview validation, owner-only import gating, duplicate receipt skipping, and "import creates no report records".

### Notes

- Import is CSV-only (header row required); exported multi-section report CSVs are not import sources.
- Legacy `export_history` rows with status `imported` may still appear in the owner inbox (historical data); new ones can only be authored by staff.
