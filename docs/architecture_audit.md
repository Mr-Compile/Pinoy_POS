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

## Verification

- `flutter analyze` — no issues found.
- `flutter test` — 150 tests passed.

