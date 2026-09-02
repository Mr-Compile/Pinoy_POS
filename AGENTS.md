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
