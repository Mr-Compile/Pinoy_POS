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

- `lib/services/receipt_service.dart`
  - Receipt export now passes `mimeType: 'application/pdf'`, preserving the PDF pipeline.

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
  - `test/backup_service_test.dart` - compile/construct smoke test for the updated `BackupService`.

### Verification

Run the focused test suite:

```powershell
flutter test test/file_type_utils_test.dart test/payment_proof_service_test.dart test/gcash_payment_service_test.dart
```

Result: 52/52 tests passed.

`flutter analyze` still reports 12 pre-existing errors in `lib/providers/dashboard_provider.dart`, `lib/services/dashboard_service.dart`, `lib/services/sales_analytics_service.dart`, and `lib/ui/screens/dashboard_screen.dart` (missing parameters/getters and an unused import). These are unrelated to the GCash payment proof flow and were present before this work.

### Receipt PDF Regression Check

`gcash_payment_service_test.dart` includes `receipt PDF is generated with non-zero bytes` and passes. `ReceiptService.saveReceiptToFile` still uses `FileType.custom` / `allowedExtensions: ['pdf']` and now passes `mimeType: 'application/pdf'`, so the PDF export pipeline remains separate from the image proof pipeline.
