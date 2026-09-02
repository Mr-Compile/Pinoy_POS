# Pinoy POS Architecture Audit

**Date:** 2026-08-28
**Scope:** Full Flutter/Dart codebase (`lib/`) — UI, providers, services, repositories, DAOs, database, core, AI, backup, export, auth, routing, permissions

## Current Architecture

```
UI (ConsumerStatefulWidget / ConsumerWidget)
 ↓ ref.watch / ref.read
Provider (StateNotifier / FutureProvider / plain Provider)
 ↓
Service
 ↓
Repository
 ↓
DAO (BaseDao<T>)
 ↓
SQLite via DatabaseHelper
```

Shared infrastructure lives in `lib/core/` (auth, permissions, navigation, theme, constants). Domain features are grouped under `lib/services/`, `lib/data/repositories/`, and `lib/data/dao/`. The project uses `flutter_riverpod`, `sqflite`, `sqflite_common_ffi`, and a Groq-backed AI advisor.

## Inventory

| Layer | Count | Notes |
|-------|-------|-------|
| UI screens | 32 | in `lib/ui/screens/` |
| UI widgets | 26 | in `lib/ui/widgets/` |
| Providers / notifiers | 11 | in `lib/providers/` |
| Service classes | 23 | in `lib/services/` |
| Repository classes | 16 | in `lib/data/repositories/` |
| DAO classes | 15 | in `lib/data/dao/` |
| Model classes | 22 | in `lib/data/models/` |
| Core classes | 16 | in `lib/core/` |

## Findings

### 1. Duplicate and overlapping responsibilities

#### 1.1 Sales / report query logic duplicated

- `SalesService.getTodaySales`, `getMonthSales`, `getSalesByDateRange`, `getFilteredSales`, `getAllSales` (`lib/services/sales_service.dart`)
- `ReportService.getTodaySales`, `getMonthSales`, `getSalesByDateRange`, `getAllSales` (`lib/services/report_service.dart`)
- `BusinessIntelligenceService` also runs its own date-range and aggregation SQL for AI facts (`lib/services/business_intelligence_service.dart`)

All three apply the same staff-vs-all role filter and call the same `SaleRepository` methods. The duplication means a change to sales reporting rules must be made in three places.

#### 1.2 Dashboard / report / BI analytics DTOs overlap

- `DailySalesPoint` exists in `lib/services/dashboard_service.dart` and `lib/services/report_service.dart` with nearly identical fields (`date`, `total`, count vs. `transactionCount`).
- `TopProductStat` and `TopProductResult` are separate DTOs in `dashboard_service.dart` and `report_service.dart`.
- `BusinessIntelligenceService` builds similar aggregate strings privately instead of reusing shared DTOs.

#### 1.3 AI usage and quota services overlap

- `AIUsageService.canUseAI`, `getTodayUsageCount`, `getRemainingQueries`, `getDailyQuota` all delegate to `AIQuotaService`. (`lib/services/ai_usage_service.dart`)
- `AIQuotaService` is the authoritative quota authority. `AIUsageService` now primarily records query history. The duplication of quota API surface is acceptable but could be simplified.

#### 1.4 Two AI navigation classes

- `AINavigationService` maps natural-language queries to `AIResponse` navigation payloads. (`lib/services/ai_navigation_service.dart`)
- `AINavigationResolver` validates and executes `AIAction` navigation. (`lib/services/ai_navigation_resolver.dart`)

They are complementary, but each carries its own destination validation logic, permission checks, and how-to text assembly. They could share a single validator.

### 2. Layer violations

#### 2.1 Services bypass the Repository/DAO boundary

- `BusinessIntelligenceService` imports `lib/data/dao/sale_item_dao.dart` directly and calls `SaleItemDao`. (`lib/services/business_intelligence_service.dart:4`)
- `SalesService` holds a `DatabaseHelper` singleton and starts its own cross-table transactions. (`lib/services/sales_service.dart:2`, `lib/services/sales_service.dart:32`)
- `StockService` also holds `DatabaseHelper` directly. (`lib/services/stock_service.dart:2`, `:17`)
- `BackupService` directly attaches to a backup SQLite file and executes raw SQL. (`lib/services/backup_service.dart:9`, `:71`, `:738`)

`BusinessIntelligenceService` and `SalesService` should route sale-item and transactional work through `SaleItemRepository` (or a new `SalesTransactionService`) instead of the DAO/SQLite helper.

#### 2.2 UI constructs services directly

- `AIQuotaManagementPage` creates `AIQuotaService()` and `UserService()` directly instead of using `ref.read`. (`lib/ui/screens/ai_quota_management_page.dart`)
- Several screens import and instantiate `ImageService()` directly: `sale_detail_screen.dart`, `receipt_screen.dart`, `profile_screen.dart`, `payment_proof_viewer_screen.dart`, `gcash_payment_screen.dart`, `products_screen.dart`, `app_image.dart`.
- `login_screen.dart`, `pin_lock_screen.dart`, and `force_change_password_screen.dart` import `lib/services/auth_service.dart` directly.

#### 2.3 Core depends on UI and services

- `lib/core/auth_navigation.dart` imports `lib/ui/app_shell.dart`, `lib/providers/auth_provider.dart`, and auth screens.
- `lib/core/route_guard.dart` imports `lib/ui/screens/access_denied_screen.dart`, `lib/ui/widgets/app_dialog_service.dart`, and providers.
- `lib/core/ai_navigation_registry.dart` imports every `lib/ui/screens/*.dart` file.
- `lib/core/ai_capability_policy.dart` imports `lib/services/business_intelligence_service.dart`.

A `core/` layer should only depend on `data/` and `dart:*/flutter:*` packages. Navigation metadata (route names and permission keys) should live in `core/`; widget builders should stay in `ui/`.

### 3. Redundant providers / state

#### 3.1 Mixed Riverpod and `setState`

- `POSScreen`, `SalesScreen`, `ProductsScreen`, `CategoriesScreen`, `StockScreen`, `AnnouncementsScreen`, `ReportsScreen`, `ReceiptScreen`, `SaleDetailScreen`, `AIQuotaManagementPage`, and others keep `List<...>` and `_isLoading` in local `setState`.
- They read service providers (`ref.read(productServiceProvider)`, etc.) and call `setState` directly.

This duplicates the loading/error/empty state work already handled by `StateNotifier` providers elsewhere in the app.

#### 3.2 Circular provider imports

- `lib/providers/auth_provider.dart` imports `lib/providers/ai_advisor_provider.dart` and `lib/providers/user_provider.dart`.
- `lib/providers/ai_advisor_provider.dart` imports `lib/providers/auth_provider.dart`.
- `lib/providers/user_provider.dart` imports `lib/providers/auth_provider.dart`.

The cycles are currently used for cross-provider invalidation but increase coupling and test difficulty.

#### 3.3 User state in three places

- `SessionManager.currentUser` (`lib/core/session_manager.dart`)
- `AuthService.currentUser` (`lib/services/auth_service.dart`)
- `AuthState.user` (`lib/providers/auth_provider.dart`)

`SessionManager` is the intended single source of truth, but the other two mirror it.

### 4. Permissions and role issues

#### 4.1 Permission strings are magic and repeated

- Role↔permission maps live in `SessionManager` (`lib/core/session_manager.dart` lines 72–165).
- Over 200 `hasPermission('...')` calls use string literals across UI, services, and AI.
- `AINavigationRegistry` redeclares `requiredPermission` and `allowedRoles` for every destination.
- No typed `Permissions` constants class exists.

#### 4.2 Duplicate owner permission entries

`SessionManager._ownerPermissions` lists `'view_payment_evidence'` and `'verify_payments'` twice. (`lib/core/session_manager.dart:88–89` and `:97–98`)

#### 4.3 Permission/role mismatch in AI navigation

- `AINavigationRegistry` destinations `users` (`requiredPermission: 'manage_users'`, `allowedRoles: [owner, admin]`) and `backup_restore` (`requiredPermission: 'backup_restore'`) do not match `SessionManager`'s owner permission list. The role and permission filters can disagree.

### 5. Routing and navigation

#### 5.1 No named-route registry

- `MaterialApp` in `lib/main.dart` only sets `home: SplashScreen()`.
- Navigation uses a mix of `Navigator.push`, `Navigator.pop`, `AuthPhaseNavigator`, `SafeNavigator.pushUnique`, `RouteGuard.pushIfAuthorized`, and `AINavigationResolver`.

#### 5.2 Route guard underused

- `RouteGuard` is only used in `dashboard_screen.dart` and `more_screen.dart`.
- Most screens push `MaterialPageRoute` directly, scattering route logic.

### 6. Security and hardcoded values

- `SecurityHelper` uses unsalted SHA-256 for passwords and PINs. (`lib/core/security.dart:8–32`)
- `AppSecurityConstants` hardcodes `superAdminPassword = 'SuperAdmin'`. (`lib/core/app_security_constants.dart:10`)
- `AppConstants.defaultTemporaryPassword = '@Password123'` is used in seeding and user reset. (`lib/core/constants.dart:25`)
- `maxDailyAIQueries = 10` is marked legacy and not used anywhere; the real default is `aiDailyQuota = 20`.

### 7. DAO / database inconsistencies

- `TrashDao` does not extend `BaseDao<TrashItem>` and directly calls `DatabaseHelper().database`. All other DAOs extend `BaseDao<T>`. (`lib/data/dao/trash_dao.dart`)
- `DatabaseSeeder` directly calls `db.query` and `db.insert` for seeding. (`lib/core/database_seeder.dart`)
- `TrashDao` imports `core/database.dart` to obtain the `Database` reference, whereas `BaseDao` also manages the database. This duplicates the database access pattern.

### 8. AI architecture

- `AIAdvisorService` correctly enforces permission, quota, model validation, capability policy, and `BusinessIntelligenceService` before calling `GroqService`.
- `BusinessIntelligenceService` is a 2300+ line service that directly imports a DAO, contains private formatting helpers (`_formatMoney`, `_formatDate`, `_formatFileSize`), and owns both intent detection and fact gathering. It has become a god class for AI analytics.
- `AiResponsePolicy` and `AIAdvisorService._buildSystemPrompt` both shape AI output; the split is not always obvious.

### 9. Dead / obsolete / unused code

- `AppConstants.maxDailyAIQueries` is not referenced in `lib/`.
- Multiple permission strings in `SessionManager._ownerPermissions` are duplicated, not dead.
- No clearly unreferenced classes were found, but several services (`external_link_validator`, `super_admin_verification_service`) are small and may be candidates for folding into larger services if their responsibility stays narrow.

### 10. Backup / restore / export

- `BackupService` correctly owns backup/restore and uses platform-specific `BackupStorageService` implementations.
- `ReceiptService` and `ReportService` both produce PDFs; `ReportService` also produces CSV/Excel. The two PDF formatters are separate, which is appropriate (receipt vs. report), but shared PDF helpers could be extracted.
- `ReportService` contains both business analytics queries and export file generation; the query portion overlaps with `SalesService` and `BusinessIntelligenceService`.

## Consolidation Plan

| # | Old / duplicated | Authoritative target | Action |
|---|------------------|----------------------|--------|
| 1 | `ReportService.getTodaySales`, `getMonthSales`, `getSalesByDateRange`, `getAllSales` | `SalesService` | Make `ReportService` delegate to `SalesService` for sales list/date-range queries. |
| 2 | `BusinessIntelligenceService` direct `SaleItemDao` access | `SaleItemRepository` | Add needed methods to `SaleItemRepository` and route BI through it. |
| 3 | Duplicate `DailySalesPoint` / `TopProduct...` DTOs | New shared analytics models in `lib/data/models/` | Merge DTOs if fields are compatible; keep domain-specific variants if not. |
| 4 | `TrashDao` not using `BaseDao` | `BaseDao<TrashItem>` | Refactor `TrashDao` to extend `BaseDao`. |
| 5 | Duplicate owner permission strings in `SessionManager` | `SessionManager` | Remove the duplicate entries. |
| 6 | Magic permission strings everywhere | New `Permissions` constants class | Introduce a constants file and replace literals. |
| 7 | UI `setState` + service provider pattern | New `FutureNotifier` / `FutureProvider` families | Convert POS, Sales, Products, Categories, Stock, etc. screens to watch providers. |
| 8 | `core/` importing UI/widgets | `core/` | Move widget builders / screen imports out of `core/`; keep only route names and permission metadata. |
| 9 | `BusinessIntelligenceService` god class | Split into `IntentDetectionService` + `FactsService` + `Formatters` | Decompose after the DAO layer is fixed. |
| 10 | `AIUsageService` quota facade | `AIQuotaService` | Consider folding quota-only methods into `AIQuotaService`; keep `AIUsageService` for query history. |

## Remaining Technical Debt

- Unsalted SHA-256 password/PIN hashing should be replaced with a salted, key-stretching algorithm (PBKDF2, bcrypt, or Argon2).
- Hardcoded `superAdminPassword` and `defaultTemporaryPassword` should move to secure configuration or first-run setup.
- No centralized named-route registry exists; navigation remains ad-hoc.
- No typed permission constants exist; string literals are scattered across the app.
- `BusinessIntelligenceService` is too large and directly accesses a DAO.

## Follow-up Items

1. Run `flutter analyze` and `flutter test` after each consolidation.
2. Add characterization tests for `SalesService` and `ReportService` before merging them.
3. Search for and remove all remaining raw `Navigator.push` call sites once a route registry is in place.
4. Document why `BackupService` and `SalesService` keep direct `DatabaseHelper` access (transactional / attach-attach requirements) if the decision is to keep them as specialized exceptions.
5. Review `AINavigationRegistry` and `SessionManager` permission lists for consistency after the `Permissions` constants class is introduced.

## Consolidation Actions Taken

1. **`lib/core/session_manager.dart`** — Removed duplicate `view_payment_evidence` and `verify_payments` entries in `_ownerPermissions`.
2. **`lib/services/business_intelligence_service.dart`** — Replaced direct `SaleItemDao` dependency with `SaleItemRepository` so BI queries flow through the repository/DAO boundary.
3. **`lib/data/repositories/notification_repository.dart`** — Added `hasUnreadNotification(...)` and `DatabaseExecutor? txn` wrapper.
4. **`lib/services/notification_service.dart`** — Stopped instantiating `NotificationDao` directly; now uses `NotificationRepository.hasUnreadNotification(...)`.
5. **`lib/data/dao/trash_dao.dart`** — Refactored `TrashDao` to extend `BaseDao<TrashItem>` while keeping trash-specific `deleteByEntity`, `getByEntityType`, and `getByEntity` helpers.
6. **`lib/services/settings_service.dart`** — Added `getStoreInfo()`, `isStoreInfoIncomplete()`, and `refreshStoreInfo()` as the canonical source for store metadata used by receipts, reports and exports.
7. **`lib/services/sales_service.dart`** — Replaced `ReportService.getStoreInfo()` call with `SettingsService.getStoreInfo()` and removed the `SalesService -> ReportService` dependency.
8. **`lib/services/report_service.dart`** — Delegated `getTodaySales()`, `getMonthSales()` and `getSalesByDateRange()` to `SalesService`; removed the duplicate `getAllSales()` path. This eliminates a circular service dependency and the duplicated date-range sales queries.
9. **`lib/data/models/daily_sales_point.dart`** and **`lib/data/models/top_product_result.dart`** — Extracted shared analytics DTOs so `ReportService` and `DashboardService` no longer duplicate them.

## 11. Backup / restore Android issues (SAF + file picker)

### 11.1 Root causes found

1. **Write mode `rwt` was not supported by every SAF document provider.**
   - `MainActivity.createDocument()` opened the newly-created document with `"rwt"`.
   - Several providers (and some Android versions) reject `"rwt"` for a fresh document, producing the `WRITE_FAILED` / "not allowed to write" errors.

2. **Restore used `file_picker` with `allowedExtensions: ['db']` on Android.**
   - Android's document picker filters by MIME type, not by extension.
   - `.db` has no standard MIME mapping, so the picker often hides valid backups.

3. **Android manifest was missing storage and network permissions.**
   - `src/main/AndroidManifest.xml` had no `INTERNET`, `READ_EXTERNAL_STORAGE`, or `WRITE_EXTERNAL_STORAGE` entries.
   - Release builds would run without network permission and the file picker fallback had no declared storage permissions.

4. **`MainActivity.openDocumentTree()` did not verify the persisted write grant.**
   - If a provider returned a tree URI but did not persist write access, the app still reported success and failed later at write time.

5. **`MainActivity.isUriValid()` queried tree URIs directly.**
   - A direct `ContentResolver.query()` on a tree URI fails on some providers, causing the saved location to be marked invalid unnecessarily.

6. **Backup file names had second-level precision.**
   - `BackupService._generateBackupFileName()` used `yyyy-MM-dd_HH-mm-ss`, so two exports in the same second could collide.

### 11.2 Fixes applied

- `android/app/src/main/AndroidManifest.xml` — added `INTERNET`, `READ_EXTERNAL_STORAGE`, and `WRITE_EXTERNAL_STORAGE` permissions.
- `android/app/src/main/kotlin/com/pinoypos/pinoy_pos/MainActivity.kt`:
  - `createDocument()` now tries `"w"`, `"wt"`, and the default `openOutputStream()` modes, and catches `SecurityException` with a clear "not allowed to write" message.
  - `openDocumentTree()` verifies the persisted write grant and returns `PERMISSION_DENIED` if it is not actually persisted.
  - `isUriValid()` builds a proper document URI for tree URIs via `DocumentsContract.buildDocumentUriUsingTree()` before querying.
  - `getDisplayName()` falls back to `DocumentsContract.Document.COLUMN_DISPLAY_NAME` when `OpenableColumns.DISPLAY_NAME` is absent.
- `lib/services/backup_storage_service_io.dart`:
  - Android restore now calls the method channel `openDocument` (using the existing `MainActivity.openDocument` handler) with a broad `*/*` filter, then validates the SQLite header afterward.
  - Android backup creation uses `application/octet-stream` instead of `application/x-sqlite3`, because some providers reject the less common SQLite MIME type.
- `lib/services/backup_service.dart` — `_generateBackupFileName()` now includes milliseconds (`yyyy-MM-dd_HH-mm-ss-SSS`) to avoid name collisions.

### 11.3 Remaining gaps

- The Android method channel still loads the entire backup file into memory for restore. Very large databases may need a streaming copy to a temporary file instead.
- iOS and other non-Android, non-web targets still use `file_picker` with `allowedExtensions: ['db']`; that path should also be tested and may need a platform-specific fix.
- No unit or integration tests currently cover backup/restore; the SAF path can only be fully exercised on a physical Android device or emulator.

## Verification

- `flutter analyze` — no issues found.
- `flutter build apk --debug` — built successfully.
- `flutter test` — 150 tests passed; 7 pre-existing `database is locked` failures in `gcash_payment_service_test.dart` / `app_header_test.dart` (Windows `sqflite_common_ffi` concurrency issue, unrelated to backup).

## Modal/Dialog Architecture Audit

Date: current session
Scope: All modal and dialog flows in `lib/ui/`, `lib/core/modal_result.dart`, and `test/dialog_dismiss_test.dart`.

### Components audited
- `AppDialog`, `AppDialogService`, `AppMessages`
- Details modals (`_StockHistoryDialog`, receipt, payment proof)
- Edit modals (users, products, categories, AI quota, settings)
- Confirmation dialogs (delete, restore, reset, toggle, unsaved changes)
- Provider/controller state (`UserController`)
- Navigation/dismissal patterns (`Navigator.pop`, `useRootNavigator`, `barrierDismissible`)
- Error handling (`AppDialogService.error`, `SnackBar`)
- Automated tests (`test/dialog_dismiss_test.dart`)

### Key findings
1. Inconsistent result values: `users_screen` previously returned `false` for both cancel and save failure.
2. AI quota dialogs used `showDialog<void>` and unconditionally parsed the input after the dialog closed, so pressing Cancel still saved.
3. `categories_screen` passed `isSaving` by value to `_saveCategory`, so the loading state never updated.
4. `products_screen` and `categories_screen` could call `setState`/`setSaving` on an already-popped dialog in their `finally` blocks.
5. Several inline `showDialog` calls did not use `useRootNavigator: true`, so success/error overlays and `Navigator.pop` could target different navigators.
6. No shared, type-safe dialog result model existed; each screen invented its own result value.

### Root causes
- No shared `ModalResult` abstraction.
- `StatefulBuilder` captures local state by value and has no lifecycle `dispose`.
- Direct service calls inside dialog `onPressed` handlers without a clear save/cancel gate.

## Changes Made

### Shared result model
- Added `lib/core/modal_result.dart`:
  - `ModalResult<T>` with `saved`, `confirmed`, `cancelled`, `dismissed`, `failed`.
  - Helpers `isSaved`, `isCancelled`, `isFailed`, `isSuccess`, `when`, `whenOrDefault`.
  - A `ModalResult` is never `null` for cancel; callers always receive a typed, unambiguous value.

### `lib/ui/screens/users_screen.dart`
- Removed the ad-hoc `EditUserResult` enum.
- `_editUser` now returns `ModalResult<void>`.
- Cancel, back-press, and discard consistently pop `ModalResult.cancelled()`.
- Save pops `ModalResult.saved()` on success and `ModalResult.failed(error: ...)` on a real service failure.
- Added `PopScope` (`canPop: false`) to block accidental back-press while saving or with unsaved changes.
- `Cancel` button is disabled while saving.
- Uses `useRootNavigator: true`.

### `lib/ui/screens/ai_quota_management_page.dart`
- `_changeDefaultQuota` and `_editUserQuota` now return `ModalResult<...>` instead of `void`.
- Save pops the parsed value in `ModalResult.saved(...)`; Cancel pops `ModalResult.cancelled()`.
- The caller only executes the service call when `result.isSaved` is true, so Cancel/Back no longer save.
- Controllers are disposed after the dialog closes.
- Uses `useRootNavigator: true`.

### `lib/ui/screens/categories_screen.dart`
- Added `ModalResult<void>` and `useRootNavigator: true` to the category dialog.
- Changed `_saveCategory` to use a `ValueChanged<bool>` setter instead of a captured `bool` value.
- `_saveCategory` receives the dialog `BuildContext` and checks `dialogContext.mounted` before any `setSaving`, `Navigator.pop`, or `AppDialogService` call.
- `TextFormField` and `Cancel` are disabled while saving.
- The dialog no longer calls `setSaving(false)` after it has been popped.
- `TextEditingController` is disposed after `await showDialog`.

### `lib/ui/screens/products_screen.dart`
- Added `ModalResult<void>` and `useRootNavigator: true` to the product dialog.
- `_saveProduct` now receives the dialog `BuildContext` and checks `dialogContext.mounted` before any UI mutation.
- Removed the unused `StateSetter` parameter.
- `LoadingButton` and `Cancel` are disabled while saving.
- `setSaving(false)` in `finally` is guarded by `dialogContext.mounted`.
- Name, price, and stock `TextEditingController`s are disposed after the dialog closes.

### Additional dialogs updated
- `lib/ui/screens/sales_screen.dart`
  - `_showSearchDialog` and `_showFilterDialog` now use `useRootNavigator: true`.
  - `_showFilterDialog` uses local `selectedMethod`/`selectedStatus` copies so cancelling no longer mutates the screen's filter state.
- `lib/ui/screens/stock_screen.dart`
  - `_showStockHistory` (details modal) uses `useRootNavigator: true` and only displays pre-fetched data; it never writes to the database on close.

### Verification
- `flutter analyze` — no issues found.
- `flutter test` — 159 tests passed, including the new `modal_result_test.dart` regression tests.
- Manual UI trace: Cancel in the user-edit, category, product, and AI-quota dialogs no longer triggers a database write or an error dialog.

### Remaining gaps
- Raw `showDialog<bool>` confirmation dialogs in `trash_screen`, `settings`, and `ai_quota` resets still use `bool?`. They correctly check `confirmed == true`, so they do not have the cancel-saves/failure bug, but they have not been migrated to `ModalResult`.
- `AppDialogService.emptyCart()` and `AppDialogService.adjustStockConfirm()` are defined but never invoked; they can be removed or wired up in a follow-up.
- No `ref.listen` error listeners exist; error display is currently imperative inside `onPressed` callbacks.

## Final Change Record

| File | Change | Reason |
|------|--------|--------|
| `lib/core/modal_result.dart` | New shared result model | Single, unambiguous dialog result semantics |
| `lib/ui/screens/users_screen.dart` | `_editUser` uses `ModalResult<void>`; `PopScope`; root navigator | Cancel is no longer treated as failure; back respected; no state updates on disposed widget |
| `lib/ui/screens/ai_quota_management_page.dart` | Quota input dialogs return `ModalResult`; cancel no longer saves | Avoid DB side effect on cancel/dismiss |
| `lib/ui/screens/categories_screen.dart` | `ModalResult<void>`; `ValueChanged<bool>`; dialog context; root navigator | Fix loading state and async lifecycle |
| `lib/ui/screens/products_screen.dart` | `ModalResult<void>`; dialog context; root navigator; controller dispose | Fix async lifecycle and navigator consistency |
| `lib/ui/screens/sales_screen.dart` | `useRootNavigator: true`; filter dialog local state | Consistent root navigator; state lifecycle |
| `lib/ui/screens/stock_screen.dart` | `_showStockHistory` uses `useRootNavigator: true` | Consistent details dialog navigation |
| `test/modal_result_test.dart` | Unit and widget tests for `ModalResult` | Regression tests for shared dialog infrastructure |

## Theme, Color, Backup & Export Audit + Repair

Date: 2026-09-02
Scope: Full audit of theme architecture, semantic colors, dark/light mode, notification bell, dialogs, backup/restore, and export.

### Audit findings

1. **Notification bell invisible (CRITICAL)** — `Badge` widget in `notification_bell.dart` had no `child` property set, so no bell icon rendered at all. The button was clickable but visually empty.
2. **Appearance settings selected state** — Selected theme option used `cs.onSurface` instead of `cs.primary` for icon/trailing color, making selection indistinguishable from unselected.
3. **No WAL checkpoint before backup** — `_prepareBackupFile()` and `_createSafetyBackup()` copied the database file without first flushing the WAL. If WAL mode were ever enabled, recent writes stored only in the `-wal` file would be missing from the backup.
4. **No integrity check on backup validation or post-restore** — `_validateBackupFile()` checked the SQLite header and required tables but did not run `PRAGMA integrity_check`. A torn or corrupted file could pass validation and destroy the live database on restore. `_performRestore()` copied the file and reopened the database without verifying the restored file was structurally sound.
5. **Incomplete provider invalidation after restore** — `_invalidateAllProviders()` missed `dashboardProvider`, `reportsProvider`, `cartProvider`, `paymentSettingsProvider`, `authStateProvider`, `aiAdvisorChatProvider`, `dashboardServiceProvider`, `receiptServiceProvider`, `imageServiceProvider`, and `businessIntelligenceServiceProvider`. After a restore, the dashboard and reports screens would show stale data.
6. **Receipt PDF used default Helvetica** — The receipt and report PDFs used the pdf package's default Helvetica font instead of the app's Inter font. While the wrapping code (`Expanded` + `softWrap: true`) was correct, using a different font than the UI meant text measurement didn't match, which could cause unexpected wrapping in edge cases.
7. **No CSV export** — The `csv` package was a dependency but unused. The reports screen only offered PDF and Excel. Users who needed a plain-text spreadsheet format had no option.

### What was already correct

- **Semantic color architecture** — `AppSemanticColors` in `app_theme.dart` is the single source of truth. All hardcoded `Color(0x...)` values are confined to this class. No `Colors.blue`, `Colors.black`, etc. found anywhere in `lib/`.
- **Material 3 ColorScheme** — Both light and dark themes are generated from `ColorScheme.fromSeed()` seeded with the semantic primary, with per-brightness error role resolution.
- **Dialog system** — `AppDialog` and `AppDialogService` use semantic colors (success/error/warning/info) consistently with brightness-aware resolution.
- **Backup storage architecture** — `BackupService` → `BackupStorageService` correctly delegates platform-specific work (Android SAF, Windows file picker, Web download) to separate implementations.
- **Backup validation** — Already checked SQLite header, required tables, and `backup_metadata` app name. The integrity check added here complements these.
- **Restore safety backup** — Already creates a safety backup before restore and rolls back on failure.
- **Export destination UX** — Both PDF and Excel exports use `FileExportService.saveBytes()` which presents a native save dialog on desktop and uses the platform save mechanism on mobile.

### Changes made

| File | Change | Reason |
|------|--------|--------|
| `lib/ui/widgets/notification_bell.dart` | Added `child: Icon(...)` to `Badge`; bell icon uses `onSurfaceVariant` (read state: `primary`); added tooltip with unread count | Fix invisible notification bell — the root cause was a missing Badge child |
| `lib/ui/screens/settings/appearance_settings_page.dart` | Selected theme option now uses `cs.primary` for icon and trailing check icon | Make selected state visually distinct from unselected |
| `lib/services/backup_service.dart` | Added `PRAGMA wal_checkpoint(TRUNCATE)` before copying DB in `_prepareBackupFile()` and `_createSafetyBackup()` | Ensure WAL writes are flushed into the main file before backup copy |
| `lib/services/backup_service.dart` | Added `PRAGMA integrity_check` to `_validateBackupFile()` and post-restore verification in `_performRestore()` | Reject corrupted backups before restore; verify restored DB is structurally sound |
| `lib/ui/screens/backup_restore_screen.dart` | `_invalidateAllProviders()` now invalidates dashboard, reports, cart, payment settings, auth, AI chat, BI, receipt, image, and dashboard service providers | Prevent stale UI after restore |
| `lib/services/pdf_font_service.dart` | New shared service that loads and caches Inter TTF fonts for PDF generation | Single source of truth for PDF fonts; prevents Helvetica fallback |
| `lib/services/receipt_service.dart` | Uses `PdfFontService` for Inter font in receipt PDF; all text styles use `_style()` helper | Consistent typography with app UI; correct text measurement prevents wrapping bugs |
| `lib/ui/screens/reports_screen.dart` | PDF export uses `PdfFontService` for Inter font | Consistent typography with receipt PDF and app UI |
| `lib/ui/screens/reports_screen.dart` | Added `ExportFormat.csv`; new `_exportToCsv()` method with proper CSV escaping via `ListToCsvConverter`; three format cards (PDF/Excel/CSV) | Users can now export sales data as CSV with proper escaping |
| `test/app_header_test.dart` | Two new regression tests: bell icon visible with non-transparent color; filled bell shown when unread > 0 | Verify the notification bell fix and prevent regression |

### Verification

- `flutter analyze` — No issues found.
- `flutter test` — 161 tests passed (159 original + 2 new notification bell regression tests).


