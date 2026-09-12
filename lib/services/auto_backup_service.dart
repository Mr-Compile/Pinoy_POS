import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

import 'package:pinoy_pos/data/models/auto_backup_settings.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';

/// Schedules and runs automatic database backups.
///
/// The service is deliberately decoupled from the UI and user session:
/// it reads the schedule directly from [SettingsRepository] so the
/// scheduler can run before anyone has logged in.
class AutoBackupService {
  final SettingsRepository _settingsRepository = SettingsRepository();
  final BackupService _backupService = BackupService();
  final NotificationService _notificationService = NotificationService();
  final UserRepository _userRepository = UserRepository();

  bool _isRunning = false;

  /// Runs a backup if the configured schedule says one is due.
  ///
  /// This is a no-op when:
  /// - automatic backups are disabled,
  /// - the platform is web,
  /// - a backup run is already in progress,
  /// - no backup location is configured,
  /// - the next scheduled run is still in the future.
  Future<void> runIfDue() async {
    if (kIsWeb) return;
    if (_isRunning) return;

    var settings = await _settingsRepository.getSettings();
    if (settings == null) return;
    if (!settings.autoBackupEnabled) return;

    final now = DateTime.now();

    // Self-heal: schedules saved before the auto_backup_scheduled_at column
    // existed have no anchor. Persist one now so the schedule becomes a
    // fixed date instead of drifting with the current date.
    if (settings.autoBackupScheduledAt == null &&
        settings.autoBackupLastRun == null) {
      settings = settings.copyWith(
        autoBackupScheduledAt: now,
        updatedAt: now,
      );
      await _settingsRepository.update(settings);
    }

    final pendingRun = _computePendingRun(settings);
    if (pendingRun == null || pendingRun.isAfter(now)) return;

    _isRunning = true;
    try {
      final savedLocation = await _backupService.getSavedBackupLocation();
      if (savedLocation == null || savedLocation.isNone) {
        _log('Automatic backup skipped: no backup location configured');
        return;
      }

      final valid = await _backupService.isLocationValid(savedLocation);
      if (!valid) {
        _log('Automatic backup skipped: configured location is not accessible');
        return;
      }

      final result = await _backupService.exportAutomaticBackup();
      if (result.result == BackupExportResult.success) {
        final updated = settings.copyWith(
          autoBackupLastRun: now,
          updatedAt: now,
        );
        await _settingsRepository.update(updated);
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

  /// Computes the pending scheduled run for [settings]: the first slot
  /// after the schedule anchor. When it is at or before now, a backup
  /// is due.
  DateTime? _computePendingRun(Settings settings) {
    final schedule = AutoBackupSettings(
      enabled: settings.autoBackupEnabled,
      frequency: settings.autoBackupFrequency,
      time: settings.autoBackupTime,
      lastRun: settings.autoBackupLastRun,
      scheduledAt: settings.autoBackupScheduledAt,
    );
    return AutoBackupSettings.computePendingRun(schedule);
  }

  Future<void> _notifyOwnerAndAdmin(BackupExportRecord result) async {
    try {
      final owners = await _userRepository.getByRole(UserRole.owner);
      final admins = await _userRepository.getByRole(UserRole.admin);

      final ownerIds = owners
          .where((u) => u.id != null)
          .map((u) => u.id!)
          .toList();
      final adminIds = admins
          .where((u) => u.id != null)
          .map((u) => u.id!)
          .toList();

      final displayName = result.displayName ?? 'pinoy_pos.db';
      final fileSize = _formatFileSize(result.fileSize);
      final now = DateTime.now();
      final when = _formatDate(now);

      if (ownerIds.isNotEmpty) {
        await _notificationService.createNotificationForUsers(
          title: 'Database automatically backed up',
          message: 'Your Pinoy POS backup ($displayName, $fileSize) '
              'was created automatically on $when.',
          type: 'backup',
          userIds: ownerIds,
        );
      }

      if (adminIds.isNotEmpty) {
        await _notificationService.createNotificationForUsers(
          title: 'Automatic backup completed',
          message: 'The scheduled backup ($displayName, $fileSize) '
              'completed successfully on $when.',
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
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} at $hour:$minute $period';
  }

  void _log(String message) {
    if (kDebugMode) {
      dev.log(message, name: 'AutoBackupService');
    }
  }
}
