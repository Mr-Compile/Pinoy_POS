# Pinoy POS

A cross-platform point-of-sale application built with Flutter for small Philippine retail stores. Runs on Android, iOS, Windows, Linux, macOS, and the web. All data stays on-device in a local SQLite database; no server required.

Currency defaults to PHP. A built-in AI Advisor analyzes sales and inventory using the Groq chat API.

## Features

- **Dashboard** — today's sales, monthly sales, low-stock count, product totals.
- **POS** — cart-based checkout with cash received and change calculation.
- **Sales** — searchable sales history, receipt numbers, void sales, sale detail view.
- **Products** — full CRUD with category assignment, low-stock thresholds, product images.
- **Categories** — full CRUD with active/inactive status.
- **Stock** — add stock and adjustments, full stock history per product.
- **Reports** — sales summaries with PDF and CSV export to the device.
- **Announcements** — pinned, expiring store-wide notices.
- **AI Advisor** — natural-language analysis of sales and inventory via Groq, capped at 10 queries per user per day.
- **Users** — admin-managed accounts with role assignment, activation, password reset, and soft delete.
- **Trash Bin** — soft-deleted records with restore and permanent purge.
- **Activity Logs** — auditable record of user actions and unauthorized access attempts.
- **Notifications** — per-user in-app notifications with read/unread state.
- **Backup & Restore** — file-based SQLite backups with history.
- **Settings hub** — profile, security, PIN, appearance, store information, AI configuration.

## Roles and Permissions

Three roles drive the navigation and feature access. The permission matrix lives in `lib/core/session_manager.dart`.

| Role | Scope |
|------|-------|
| **Owner** | Business superuser. Store operations, products, categories, stock, sales, reports, announcements, trash, activity logs, AI advisor, store settings. No user management, backups, or AI config. |
| **System Admin** | Technical administrator. User management, backups, AI config, settings, trash, activity logs. No POS, products, sales, reports, or announcements. |
| **Staff** | Daily operations. POS, products, categories, stock, own sales, own reports, profile. No delete, void, or admin tooling. |

Default seeded accounts (created on first run by `DatabaseSeeder`):

| Username | Password | Role |
|----------|----------|------|
| `owner`  | `owner123` | Owner |
| `admin`  | `admin123` | System Admin |
| `staff`  | `staff123` | Staff |

Change these passwords after your first login.

## Architecture

Layered structure under `lib/`:

```
lib/
  core/           Constants, theme, security, session manager, route guard, database helper, seeder
  data/
    dao/          Low-level SQLite access per table
    models/       Plain Dart models with toMap/fromMap/copyWith
    repositories/ DAO wrappers with business-aware queries
  services/       Use-case layer. Enforces RBAC via SessionManager, orchestrates repositories.
  providers/      Riverpod providers and state notifiers
  ui/
    screens/      Feature screens + settings sub-pages
    widgets/      Shared widgets (header, logo, dialogs, cards, messages)
```

Dependency direction: `ui → providers → services → repositories → dao → database`. Services read the current user from `SessionManager` rather than `AuthService`, which breaks the previous `AuthService → ActivityLogService → AuthService` cycle.

### State management

Riverpod 2.x with `StateNotifierProvider` for auth, dashboard, theme, users, and notifications. Service providers wrap the service layer and are invalidated on logout so no stale session state leaks between users.

### Storage

SQLite via `sqflite` on mobile and `sqflite_common_ffi` on desktop. The schema is at version 5 with incremental migrations in `lib/core/database.dart`. Tables use soft deletes (`deleted_at`) and a partial unique index on `users(username)` so soft-deleted usernames can be reused. `onCreate` is idempotent so an interrupted first run recovers instead of bricking the database.

### Security

Passwords are SHA-256 hashed in `lib/core/security.dart`. Four-digit PINs enable quick login. Sessions persist in `SharedPreferences` by user id and are revalidated against the database on restore. The Groq API key is stored in the `settings` table, passed per request to `GroqService`, and never logged.

### Navigation and access control

`AppShell` renders a `NavigationBar` on phones, a `NavigationRail` on tablets (>=600px), and an extended rail on desktop (>=900px). Tabs are filtered by role. `RouteGuard` checks permissions before pushing any secondary screen and logs unauthorized attempts to the activity log.

## Getting Started

### Prerequisites

- Flutter 3.x with Dart SDK ^3.12.2
- A connected device, emulator, or desktop target

### Install and run

```bash
flutter pub get
flutter run
```

On Windows, Linux, or macOS the app initializes the `sqflite_common_ffi` factory automatically on startup.

### Build a release

```bash
flutter build apk        # Android
flutter build ios        # iOS
flutter build windows    # Windows
flutter build macos      # macOS
flutter build linux      # Linux
flutter build web        # Web
```

## Testing

Tests use `sqflite_common_ffi` against an in-process SQLite database. Integration tests authenticate as the seeded owner and exercise the full chain: screen, service, repository, DAO, SQLite.

```bash
flutter test
flutter test --coverage
```

Test files:

- `test/owner_integration_test.dart` — Owner feature chain end to end
- `test/owner_screens_test.dart` — Owner screen widget tests
- `test/user_service_test.dart` — User management service tests
- `test/app_header_test.dart` — Shared header widget tests
- `test/widget_test.dart` — Basic widget smoke test

## Configuration

### AI Advisor

The AI Advisor calls the Groq chat completions endpoint. Configure it from Settings → AI Configuration (System Admin only):

1. Get an API key from [console.groq.com](https://console.groq.com).
2. Enter the key and a model id (for example, `llama-3.3-70b-versatile`).
3. Save. The key is stored locally in the `settings` table.

Each user is limited to `maxDailyAIQueries` (10) queries per day, tracked in the `ai_usage` table. The advisor requires an internet connection.

### Store information

Settings → Store Information (Owner only) sets the store name, address, phone, currency, and receipt footer used on exports and receipts.

## Project Layout Notes

- Branding SVGs live in `assets/branding/` and are declared in `pubspec.yaml`.
- `AppConstants` in `lib/core/constants.dart` centralizes tunable values: database version, page size, daily AI query limit, password and PIN length, low-stock threshold, max image size.
- `DatabaseHelper.resetForTest` and `recreateSchemaForTest` exist for test isolation and avoid the Windows file-lock race that breaks delete-and-reopen test setups.

## License

Private project. `publish_to: 'none'` in `pubspec.yaml` prevents accidental publication to pub.dev.
