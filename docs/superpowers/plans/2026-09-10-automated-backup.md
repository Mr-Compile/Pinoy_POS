# Automated Backup (Option A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Admin-configurable automatic database backups (every 3 days, 7 days, or once a month) to the existing Backup & Restore screen, with in-app notifications for Owners and Admins on success.

**Architecture:** Store the schedule in the `settings` table. A new `AutoBackupService` computes the next run time and delegates the actual backup to a new unattended method in `BackupService`. An `AutoBackupScheduler` (a `WidgetsBindingObserver`) checks on app startup, app resume, and every 15 minutes while the app is open, running the backup only when it is due and a backup location is configured. Success notifications are delivered to all Owner and Admin users via `NotificationService.createNotificationForUsers`.

**Tech Stack:** Flutter 3 / Dart, Riverpod, sqflite, shared_preferences, existing Pinoy POS services (`BackupService`, `SettingsService`, `NotificationService`, `UserRepository`, `SessionManager`).

## Global Constraints

- Database version is currently `24` in `lib/core/constants.dart`.
- Only Admin (`backup_restore` permission) can configure the schedule.
- All database migrations must be idempotent (`IF NOT EXISTS`, `try/catch` on `ALTER TABLE`).
- No raw `Color(0x...)` or hardcoded `BorderRadius.circular(N)` in UI code; use `AppSemanticColors`, `AppRadius`, `AppTypography`, and the shared input widgets.
- The feature must work in both light and dark mode and on portrait phone / tablet / desktop.
- No new dependencies if possible; use built-in `Timer` and `WidgetsBindingObserver`.

---

### Task 1: Database migration for auto-backup settings

**Files:**
- Modify: `lib/core/constants.dart`
- Modify: `lib/core/database.dart`

**Interfaces:**
- Consumes: current `_onUpgrade` pattern.
- Produces: new columns on the `settings` table: `auto_backup_enabled`, `auto_backup_frequency`, `auto_backup_time`, `auto_backup_last_run`.

- [ ] **Step 1: Bump database version and add migration v24 → v25**

In `lib/core/constants.dart`:

```dart
static const int databaseVersion = 25;
```

In `lib/core/database.dart`, add inside `_onUpgrade` before the final `_createTables` call:

```dart
// Migration from v24 → v25: add automatic backup schedule columns to settings.
if (oldVersion < 25) {
  const columns = [
    'auto_backup_enabled INTEGER NOT NULL DEFAULT 0',
    'auto_backup_frequency TEXT NOT NULL DEFAULT \'7_days\'',
    'auto_backup_time TEXT NOT NULL DEFAULT \'02:00\'',
    'auto_backup_last_run TEXT',
  ];
  for (final column in columns) {
    try {
      final parts = column.split(' ');
      final name = parts.first;
      await db.execute('ALTER TABLE settings ADD COLUMN $column');
    } catch (_) {
      // Column may already exist.
    }
  }
}
```

- [ ] **Step 2: Update `_createTables` settings schema**

Add the four columns to the `CREATE TABLE IF NOT EXISTS settings (...)` statement.

- [ ] **Step 3: Verify `flutter analyze` still passes**

Run:

```powershell
flutter analyze
```

---

### Task 2: Extend `Settings` model

**Files:**
- Modify: `lib/data/models/settings.dart`

**Interfaces:**
- Consumes: new database columns.
- Produces: `autoBackupEnabled`, `autoBackupFrequency`, `autoBackupTime`, `autoBackupLastRun` on `Settings`, plus `copyWith` support.

- [ ] **Step 1: Add fields and constructor defaults**

Add to the `Settings` class:

```dart
final bool autoBackupEnabled;
final String autoBackupFrequency;
final String autoBackupTime;
final DateTime? autoBackupLastRun;
```

And update the constructor defaults:

```dart
this.autoBackupEnabled = false,
this.autoBackupFrequency = '7_days',
this.autoBackupTime = '02:00',
this.autoBackupLastRun,
```

- [ ] **Step 2: Update `toMap` and `fromMap`**

`toMap`:

```dart
'auto_backup_enabled': autoBackupEnabled ? 1 : 0,
'auto_backup_frequency': autoBackupFrequency,
'auto_backup_time': autoBackupTime,
'auto_backup_last_run': autoBackupLastRun?.toIso8601String(),
```

`fromMap`:

```dart
autoBackupEnabled: boolFromInt('auto_backup_enabled'),
autoBackupFrequency: stringOrNull('auto_backup_frequency') ?? '7_days',
autoBackupTime: stringOrNull('auto_backup_time') ?? '02:00',
autoBackupLastRun: map['auto_backup_last_run'] != null
    ? DateTime.tryParse(map['auto_backup_last_run'] as String)
    : null,
```

- [ ] **Step 3: Update `copyWith`**

Add parameters:

```dart
bool? autoBackupEnabled,
String? autoBackupFrequency,
String? autoBackupTime,
Object? autoBackupLastRun = _sentinel,
```

And in the returned `Settings(...)` block:

```dart
autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
autoBackupFrequency: autoBackupFrequency ?? this.autoBackupFrequency,
autoBackupTime: autoBackupTime ?? this.autoBackupTime,
autoBackupLastRun: autoBackupLastRun == _sentinel
    ? this.autoBackupLastRun
    : autoBackupLastRun as DateTime?,
```

---

### Task 3: Settings service for the schedule

**Files:**
- Modify: `lib/services/settings_service.dart`

**Interfaces:**
- Consumes: `Settings` model.
- Produces: `getAutoBackupSettings()` returning a focused DTO, `updateAutoBackupSettings(...)` for persisting the schedule.

- [ ] **Step 1: Add a public `AutoBackupSettings` DTO at the bottom of `settings_service.dart`**

```dart
class AutoBackupSettings {
  final bool enabled;
  final String frequency;
  final String time;

  const AutoBackupSettings({
    this.enabled = false,
    this.frequency = '7_days',
    this.time = '02:00',
  });

  AutoBackupSettings copyWith({
    bool? enabled,
    String? frequency,
    String? time,
  }) =>
      AutoBackupSettings(
        enabled: enabled ?? this.enabled,
        frequency: frequency ?? this.frequency,
        time: time ?? this.time,
      );
}
```

- [ ] **Step 2: Add getter and updater methods to `SettingsService`**

```dart
Future<AutoBackupSettings> getAutoBackupSettings() async {
  if (!_sessionManager.hasPermission('backup_restore')) {
    throw AuthorizationException('backup_restore');
  }
  final settings = await getSettings();
  return AutoBackupSettings(
    enabled: settings.autoBackupEnabled,
    frequency: settings.autoBackupFrequency,
    time: settings.autoBackupTime,
  );
}

Future<bool> updateAutoBackupSettings(AutoBackupSettings schedule) async {
  if (!_sessionManager.hasPermission('backup_restore')) {
    throw AuthorizationException('backup_restore');
  }
  final current = await getSettings();
  final updated = current.copyWith(
    autoBackupEnabled: schedule.enabled,
    autoBackupFrequency: schedule.frequency,
    autoBackupTime: schedule.time,
    updatedAt: DateTime.now(),
  );
  return updateSettings(updated);
}
```

- [ ] **Step 3: Add `updateAutoBackupLastRun` helper**

```dart
Future<void> updateAutoBackupLastRun(DateTime lastRun) async {
  final current = await _settingsRepository.getSettings();
  if (current == null) return;
  final updated = current.copyWith(
    autoBackupLastRun: lastRun,
    updatedAt: DateTime.now(),
  );
  await _settingsRepository.update(updated);
  _currentSettings = updated;
}
```

---

### Task 4: Backup service — unattended export

**Files:**
- Modify: `lib/services/backup_service.dart`

**Interfaces:**
- Consumes: `BackupStorageService`, `BackupHistoryDao`, `_prepareBackupFile`, `_safeDelete`, `getSavedBackupLocation`, `_generateBackupFileName`.
- Produces: `exportAutomaticBackup()` which does not require a user session and returns the same `BackupExportRecord`.

- [ ] **Step 1: Extract the permission check from `exportBackup`**

Refactor `exportBackup` so the core logic lives in a private method `_doExportBackup({required BackupLocation? override, required bool setAsDefault})`. Public `exportBackup` keeps the permission check and then calls `_doExportBackup(override: override, setAsDefault: setAsDefault)`.

- [ ] **Step 2: Add `exportAutomaticBackup()` public method**

```dart
Future<BackupExportRecord> exportAutomaticBackup() async {
  final defaultName = _generateBackupFileName();
  final savedLocation = await getSavedBackupLocation();

  if (savedLocation == null || savedLocation.isNone) {
    return const BackupExportRecord(
      result: BackupExportResult.failed,
      error: 'No automatic backup location is configured.',
    );
  }

  final valid = await isLocationValid(savedLocation);
  if (!valid) {
    return const BackupExportRecord(
      result: BackupExportResult.failed,
      error: 'The configured backup location is no longer accessible.',
    );
  }

  return _doExportBackup(override: null, setAsDefault: false);
}
```

Ensure `_doExportBackup` passes `createdBy: null` for the automatic case (it should already be null for an unauthenticated caller, but make this explicit).

- [ ] **Step 3: Update activity log / notification in the export flow**

Change the existing backup-created notification so it can target owners/admins when `createdBy` is null. Or defer notification to `AutoBackupService`. The simpler approach is to let `AutoBackupService` handle its own notifications and keep the manual export notification targeting the current user.

---

### Task 5: Auto backup service

**Files:**
- Create: `lib/services/auto_backup_service.dart`

**Interfaces:**
- Consumes: `SettingsService.getAutoBackupSettings`, `SettingsService.updateAutoBackupLastRun`, `BackupService.exportAutomaticBackup`, `UserRepository.getByRole`, `NotificationService.createNotificationForUsers`.
- Produces: `shouldRun()`, `runIfDue()`, `nextRunTime()`.

- [ ] **Step 1: Create the service with schedule computation**

```dart
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

class AutoBackupService {
  final SettingsService _settingsService = SettingsService();
  final BackupService _backupService = BackupService();
  final NotificationService _notificationService = NotificationService();
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();

  bool _isRunning = false;

  /// Public entry point: run one backup if the schedule says it is due.
  Future<void> runIfDue() async {
    if (_isRunning) return;

    final settings = await _settingsService.getAutoBackupSettings();
    if (!settings.enabled) return;

    final nextRun = await _computeNextRun(settings);
    final now = DateTime.now();
    if (nextRun.isAfter(now)) return;

    _isRunning = true;
    try {
      final result = await _backupService.exportAutomaticBackup();
      if (result.result == BackupExportResult.success) {
        await _settingsService.updateAutoBackupLastRun(now);
        await _notifyOwnerAndAdmin(result);
      } else if (result.result == BackupExportResult.failed) {
        _log('Automatic backup failed: ${result.error}');
      }
    } catch (e, st) {
      _log('Automatic backup error: $e\n$st');
    } finally {
      _isRunning = false;
    }
  }

  Future<DateTime> _computeNextRun(AutoBackupSettings settings) async {
    final current = await _settingsService.getSettings();
    final lastRun = current.autoBackupLastRun;

    final parts = settings.time.split(':');
    final hour = int.tryParse(parts[0]) ?? 2;
    final minute = int.tryParse(parts[1]) ?? 0;

    DateTime base;
    if (lastRun == null) {
      final now = DateTime.now();
      base = DateTime(now.year, now.month, now.day, hour, minute);
      if (base.isBefore(now)) {
        // Schedule already passed today; run the next one based on frequency.
        base = _addFrequency(base, settings.frequency);
      }
    } else {
      final next = DateTime(
        lastRun.year,
        lastRun.month,
        lastRun.day,
        hour,
        minute,
      );
      base = _addFrequency(next, settings.frequency);
      // If the calculated next run is still before now, keep advancing
      // until it is in the future.
      final now = DateTime.now();
      while (base.isBefore(now)) {
        base = _addFrequency(base, settings.frequency);
      }
    }
    return base;
  }

  DateTime _addFrequency(DateTime from, String frequency) {
    switch (frequency) {
      case '3_days':
        return from.add(const Duration(days: 3));
      case '7_days':
        return from.add(const Duration(days: 7));
      case 'monthly':
        final nextMonth = from.month == 12 ? 1 : from.month + 1;
        final nextYear = from.month == 12 ? from.year + 1 : from.year;
        final day = from.day;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        return DateTime(nextYear, nextMonth, day > lastDay ? lastDay : day, from.hour, from.minute);
      default:
        return from.add(const Duration(days: 7));
    }
  }

  Future<void> _notifyOwnerAndAdmin(BackupExportRecord result) async {
    try {
      final owners = await _userRepository.getByRole(UserRole.owner);
      final admins = await _userRepository.getByRole(UserRole.admin);
      final ownerIds = owners.where((u) => u.id != null).map((u) => u.id!).toList();
      final adminIds = admins.where((u) => u.id != null).map((u) => u.id!).toList();

      final fileName = result.displayName ?? 'pinoy_pos.db';
      final fileSize = _formatFileSize(result.fileSize);
      final when = _formatDate(result.createdAt ?? DateTime.now());

      if (ownerIds.isNotEmpty) {
        await _notificationService.createNotificationForUsers(
          title: 'Database automatically backed up',
          message: 'Your Pinoy POS backup ($fileName, $fileSize) was created automatically on $when.',
          type: 'backup',
          userIds: ownerIds,
        );
      }

      if (adminIds.isNotEmpty) {
        await _notificationService.createNotificationForUsers(
          title: 'Automatic backup completed',
          message: 'The scheduled backup ($fileName, $fileSize) completed successfully on $when.',
          type: 'backup',
          userIds: adminIds,
        );
      }
    } catch (e) {
      _log('Failed to create auto-backup notifications: $e');
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _log(String message) {
    if (kDebugMode) {
      dev.log(message, name: 'AutoBackupService');
    }
  }
}
```

- [ ] **Step 2: Add a provider to `lib/providers/service_providers.dart`**

```dart
final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  return AutoBackupService();
});
```

---

### Task 6: Auto backup scheduler

**Files:**
- Create: `lib/services/auto_backup_scheduler.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `AutoBackupService.runIfDue`.
- Produces: a `WidgetsBindingObserver` that schedules periodic checks.

- [ ] **Step 1: Create `AutoBackupScheduler`**

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pinoy_pos/services/auto_backup_service.dart';

class AutoBackupScheduler with WidgetsBindingObserver {
  final AutoBackupService _service;
  Timer? _timer;

  AutoBackupScheduler({required AutoBackupService service}) : _service = service;

  void start() {
    if (kIsWeb) return; // Web has no persistent filesystem backup location.
    _runCheck();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _runCheck());
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runCheck();
    }
  }

  void _runCheck() {
    if (kDebugMode) {
      debugPrint('[AutoBackupScheduler] Checking schedule');
    }
    _service.runIfDue().catchError((e) {
      if (kDebugMode) {
        debugPrint('[AutoBackupScheduler] Check failed: $e');
      }
    });
  }
}
```

- [ ] **Step 2: Start the scheduler in `MyApp`**

Add an `initState`/`dispose` in `lib/main.dart` `_MyAppState`:

```dart
import 'package:pinoy_pos/services/auto_backup_scheduler.dart';

late final AutoBackupScheduler _autoBackupScheduler;

@override
void initState() {
  super.initState();
  _autoBackupScheduler = AutoBackupScheduler(
    service: AutoBackupService(),
  );
  _autoBackupScheduler.start();

  _navigationObserver = NavigationRouteObserver(...);
}

@override
void dispose() {
  _autoBackupScheduler.stop();
  super.dispose();
}
```

Make sure `AutoBackupService()` is instantiated once; do not use a provider here because `main.dart` is above `ProviderScope`.

---

### Task 7: UI — automated backup section on `BackupRestoreScreen`

**Files:**
- Modify: `lib/ui/screens/backup_restore_screen.dart`

**Interfaces:**
- Consumes: `SettingsService.getAutoBackupSettings`, `SettingsService.updateAutoBackupSettings`, `AppDialogService`.
- Produces: an editable automated-backup card with toggle, frequency dropdown, time picker, next-run text, and save button.

- [ ] **Step 1: Add state fields in `_BackupRestoreScreenState`**

```dart
AutoBackupSettings _autoBackupSettings = const AutoBackupSettings();
bool _autoBackupLoading = true;
bool _isSavingAutoBackup = false;
```

- [ ] **Step 2: Load settings in `initState`**

```dart
_loadAutoBackupSettings();
```

```dart
Future<void> _loadAutoBackupSettings() async {
  setState(() => _autoBackupLoading = true);
  try {
    final settings = await ref.read(settingsServiceProvider).getAutoBackupSettings();
    if (mounted) {
      setState(() {
        _autoBackupSettings = settings;
        _autoBackupLoading = false;
      });
    }
  } catch (e, st) {
    _log('Failed to load auto backup settings', e, st);
    if (mounted) setState(() => _autoBackupLoading = false);
  }
}
```

- [ ] **Step 3: Add `onPressed` to save the schedule**

```dart
Future<void> _saveAutoBackupSettings() async {
  setState(() => _isSavingAutoBackup = true);
  try {
    final success = await ref
        .read(settingsServiceProvider)
        .updateAutoBackupSettings(_autoBackupSettings);
    if (!mounted) return;
    if (success) {
      await AppDialogService.success(
        context,
        title: 'Saved',
        message: 'Automatic backup schedule updated.',
      );
    }
  } catch (e, st) {
    _log('Failed to save auto backup settings', e, st);
    if (mounted) {
      await AppDialogService.error(
        context,
        title: 'Save Failed',
        message: 'Could not save the automatic backup schedule.',
      );
    }
  } finally {
    if (mounted) setState(() => _isSavingAutoBackup = false);
  }
}
```

- [ ] **Step 4: Build the card `_buildAutomatedBackupCard(context)`**

Insert it after `_buildLocationCard(context)` in the column. The card should:
- Show a toggle for `enabled`.
- Show a dropdown for frequency (3 days / 7 days / monthly).
- Show a time picker row that opens `showTimePicker`.
- Show the next computed run time using `AutoBackupService`.
- Show a save button.
- Be disabled / show a helper if the backup location is not set.

Use `AppCard`, `AppTypography`, the shared `SwitchListTile` or `ListTile` with `Switch`, and `AppButton` where the project already uses it. The theme tokens are `AppSemanticColors.success` for enabled state and `AppSemanticColors.info` for the icon.

- [ ] **Step 5: Add the card to the main build column**

Between `_buildLocationCard(context)` and `_buildSectionHeader(context, 'Quick Actions')`.

---

### Task 8: Tests and verification

**Files:**
- Create: `test/auto_backup_service_test.dart`
- Modify: `test/backup_restore_screen_test.dart` (if it exists)

- [ ] **Step 1: Add unit tests for `_addFrequency` and `_computeNextRun`**

Create `test/auto_backup_service_test.dart` using a test harness that sets up the database and settings. Test:
- `3_days` adds 3 days.
- `7_days` adds 7 days.
- `monthly` advances one month and clamps to the last valid day.
- When `lastRun` is null and the time has passed today, the next run is in the future.

- [ ] **Step 2: Run targeted tests**

```powershell
flutter test test/auto_backup_service_test.dart
```

- [ ] **Step 3: Run project-wide checks**

```powershell
flutter analyze
flutter test --concurrency=1
```

---

## Spec Coverage

- Admin sets schedule (frequency + time) → Task 7.
- Choices: 3 days, 7 days, once a month → Task 5 `_addFrequency` and Task 7 dropdown.
- Notify owner that DB is backed up → Task 5 `_notifyOwnerAndAdmin`.
- Notify admin of success → Task 5 `_notifyOwnerAndAdmin`.
- Works as long as there is a backup path → Task 4 checks `savedLocation` and Task 5 triggers only via `BackupService.exportAutomaticBackup`.
- Functional and automates in the codebase → Tasks 5 and 6.
