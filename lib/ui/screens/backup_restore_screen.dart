import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/data/models/backup_location.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/providers/dashboard_provider.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Backup & Restore screen — Admin only.
///
/// Architecture: UI → backupServiceProvider → BackupService →
/// BackupStorageService → platform storage
///
/// The screen never touches DAOs or SQLite directly. All operations go
/// through [BackupService] which enforces the `backup_restore` permission.
///
/// State is separated into independent concerns so one failing operation
/// never blocks the rest of the screen:
///   - backup history loading  (_isLoading / _loadError)
///   - backup location loading  (_locationLoading / _locationError)
///   - selecting a location      (_isSelectingLocation)
///   - creating a backup         (_isExporting)
///   - importing / restoring     (_isImporting)
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  // ── Backup history state ──
  List<BackupHistory> _backups = [];
  bool _isLoading = true;
  String? _loadError;

  // Map of backup id → computed display strings so the list builds sync.
  final Map<int, _BackupDisplay> _displayCache = {};

  // ── Backup location state (independent of history loading) ──
  BackupLocation? _backupLocation;
  bool _locationLoading = true;

  // ── Action loading flags (independent of each other) ──
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isSelectingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadBackupLocation();
  }

  // ── Load Backup History ──────────────────────────────────────────────

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _displayCache.clear();
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final backups = await backupService.getBackupHistory();

      await _cacheDisplayNames(backups);

      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      _log('Failed to load backup history', e, st);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'We couldn\'t load your backup information. Please try again.';
        });
      }
    }
  }

  Future<void> _cacheDisplayNames(List<BackupHistory> backups) async {
    final backupService = ref.read(backupServiceProvider);
    await Future.wait(
      backups.map((b) async {
        final name = await backupService.getDisplayName(b);
        final location = await backupService.getDisplayLocationForHistory(b);
        _displayCache[b.id!] = _BackupDisplay(
          name: name,
          location: location,
        );
      }),
    );
  }

  // ── Load Saved Backup Location ───────────────────────────────────────

  Future<void> _loadBackupLocation() async {
    setState(() {
      _locationLoading = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final location = await backupService.getSavedBackupLocation();
      if (mounted) {
        setState(() {
          _backupLocation = location;
          _locationLoading = false;
        });
      }
    } catch (e, st) {
      _log('Failed to load backup location', e, st);
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _backupLocation = null;
        });
      }
    }
  }

  // ── Choose / Change Backup Location ──────────────────────────────────

  Future<BackupLocation?> _chooseBackupLocation({
    BackupLocation? initial,
    bool persist = true,
  }) async {
    if (_isSelectingLocation) return null;

    setState(() => _isSelectingLocation = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      while (mounted) {
        ({BackupLocationResult result, BackupLocation? location, String? error})
            result;
        try {
          result = await backupService.pickBackupLocation(
            initial: initial ?? _backupLocation,
            persist: persist,
          );
        } catch (e, st) {
          _log('Backup location selection failed', e, st);
          result = (
            result: BackupLocationResult.failed,
            location: null,
            error: 'An unexpected error occurred while choosing a location.',
          );
        }
        if (!mounted) return null;

        switch (result.result) {
          case BackupLocationResult.selected:
            final location = result.location;
            if (persist && location != null) {
              setState(() => _backupLocation = location);
            }
            if (persist) {
              await AppDialogService.backupLocationChanged(
                context,
                location: backupService.getDisplayLocation(location),
              );
            }
            return location;
          case BackupLocationResult.canceled:
            return null;
          case BackupLocationResult.failed:
            final retry = await AppDialogService.backupLocationSelectionFailed(
              context,
              reason: result.error,
            );
            if (!retry || !mounted) return null;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSelectingLocation = false);
      }
    }
    return null;
  }

  // ── Export Backup ────────────────────────────────────────────────────

  Future<void> _exportBackup() async {
    if (_isExporting) return;

    final backupService = ref.read(backupServiceProvider);
    final isWeb = kIsWeb;

    // On non-web platforms, a saved location is required for the default
    // "Save to saved location" flow. On web we do not need one.
    if (!isWeb && (_backupLocation == null || _backupLocation!.isNone)) {
      final choose = await AppDialogService.backupLocationRequired(context);
      if (!choose || !mounted) return;
      final location = await _chooseBackupLocation();
      if (!mounted) return;
      if (location == null || location.isNone) return;
    }

    // Validate the saved location is still accessible.
    if (_backupLocation != null && !(_backupLocation?.isNone ?? true)) {
      bool valid;
      try {
        valid = await backupService.isLocationValid(_backupLocation!);
      } catch (e, st) {
        _log('Backup location validation failed', e, st);
        valid = false;
      }

      if (!valid) {
        if (!mounted) return;
        await backupService.clearBackupLocation();
        if (!mounted) return;
        setState(() => _backupLocation = null);
        final choose = await AppDialogService.backupLocationUnavailable(context);
        if (!choose || !mounted) return;
        final location = await _chooseBackupLocation();
        if (!mounted) return;
        if (location == null || location.isNone) return;
      }
    }

    await _runExportWithOptions(backupService);
  }

  Future<void> _runExportWithOptions(BackupService backupService) async {
    final savedLocation = _backupLocation;
    final defaultDisplayName = _generateDefaultFileName();
    final savedLocationLabel = backupService.getDisplayLocation(savedLocation);

    final confirm = await AppDialogService.backupDestinationConfirm(
      context,
      displayName: defaultDisplayName,
      location: savedLocationLabel,
    );

    if (!mounted) return;

    if (confirm == BackupDestinationConfirmResult.cancel) return;

    const override = null;
    const setAsDefault = false;

    setState(() => _isExporting = true);

    try {
      while (mounted) {
        BackupExportRecord result;
        try {
          result = await backupService.exportBackup(
            override: override,
            setAsDefault: setAsDefault,
          );
        } catch (e, st) {
          _log('Backup export failed', e, st);
          result = const BackupExportRecord(
            result: BackupExportResult.failed,
            error: 'An unexpected error occurred while creating the backup.',
          );
        }
        if (!mounted) return;

        switch (result.result) {
          case BackupExportResult.success:
            final locationLabel = backupService.getDisplayLocation(
              result.writtenTo,
            );
            await AppDialogService.backupExportSuccess(
              context,
              displayName: result.displayName ?? defaultDisplayName,
              location: locationLabel,
              fileSize: _formatFileSize(result.fileSize),
            );
            await _loadBackups();
            return;
          case BackupExportResult.canceled:
            return;
          case BackupExportResult.failed:
            final action = await AppDialogService.backupExportFailed(
              context,
              reason: result.error,
            );
            if (!mounted) return;
            switch (action) {
              case BackupExportFailedResult.close:
                return;
              case BackupExportFailedResult.tryAgain:
                continue;
            }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _generateDefaultFileName() {
    final now = DateTime.now();
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);
    return 'pinoy_pos_backup_$stamp.zip';
  }

  // ── Import Backup ────────────────────────────────────────────────────

  Future<void> _importBackup() async {
    if (_isImporting) return;

    setState(() => _isImporting = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.importBackup();

      if (!mounted) return;

      switch (result.result) {
        case BackupImportResult.success:
          _invalidateAllProviders();
          await AppDialogService.backupRestoreSuccess(context);
          await _loadBackups();
        case BackupImportResult.canceled:
          break;
        case BackupImportResult.invalidFile:
          await AppDialogService.invalidBackupFile(context);
        case BackupImportResult.incompatible:
          await AppDialogService.incompatibleBackupFile(context);
        case BackupImportResult.failed:
          await AppDialogService.backupRestoreFailed(context, reason: result.error);
      }
    } catch (e, st) {
      _log('Backup import failed', e, st);
      if (mounted) {
        await AppDialogService.backupRestoreFailed(context, reason: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // ── Restore from History ─────────────────────────────────────────────

  Future<void> _restoreFromHistory(BackupHistory backup) async {
    if (_isImporting) return;

    final display = _displayCache[backup.id];
    final displayName = display?.name ?? 'backup.db';

    final confirmed = await AppDialogService.restoreBackupConfirm(
      context,
      displayName: displayName,
      fileSize: _formatFileSize(backup.fileSize),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);

    try {
      final result = await ref.read(backupServiceProvider).restoreFromHistory(backup);

      if (!mounted) return;

      switch (result.result) {
        case BackupImportResult.success:
          _invalidateAllProviders();
          await AppDialogService.backupRestoreSuccess(context);
          await _loadBackups();
        case BackupImportResult.invalidFile:
          await AppDialogService.invalidBackupFile(context);
        case BackupImportResult.incompatible:
          await AppDialogService.incompatibleBackupFile(context);
        case BackupImportResult.failed:
          await AppDialogService.backupRestoreFailed(context, reason: result.error);
        case BackupImportResult.canceled:
          break;
      }
    } catch (e, st) {
      _log('Restore from history failed', e, st);
      if (mounted) {
        await AppDialogService.backupRestoreFailed(context, reason: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // ── Delete Backup ────────────────────────────────────────────────────

  Future<void> _deleteBackup(BackupHistory backup) async {
    final backupService = ref.read(backupServiceProvider);
    final display = _displayCache[backup.id];
    final displayName = display?.name ?? 'backup.db';

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: displayName,
    );

    if (confirmed != true || !mounted) return;

    try {
      final success = await backupService.deleteBackup(backup);
      if (!mounted) return;
      if (success) {
        await AppDialogService.success(
          context,
          title: 'Deleted',
          message: 'Backup record deleted successfully.',
        );
        await _loadBackups();
      } else {
        await AppDialogService.error(
          context,
          title: 'Delete Failed',
          message: 'Failed to delete the backup record.',
        );
      }
    } catch (e, st) {
      _log('Delete backup failed', e, st);
      if (mounted) {
        await AppDialogService.error(
          context,
          title: 'Delete Failed',
          message: 'Failed to delete the backup record.',
        );
      }
    }
  }

  // ── Invalidate Providers ─────────────────────────────────────────────

  void _invalidateAllProviders() {
    // ── Service providers ──
    ref.invalidate(productServiceProvider);
    ref.invalidate(categoryServiceProvider);
    ref.invalidate(salesServiceProvider);
    ref.invalidate(stockServiceProvider);
    ref.invalidate(activityLogServiceProvider);
    ref.invalidate(notificationServiceProvider);
    ref.invalidate(notificationCountProvider);
    ref.invalidate(settingsServiceProvider);
    ref.invalidate(reportServiceProvider);
    ref.invalidate(backupServiceProvider);
    ref.invalidate(aiUsageServiceProvider);
    ref.invalidate(aiAdvisorServiceProvider);
    ref.invalidate(groqServiceProvider);
    ref.invalidate(businessIntelligenceServiceProvider);
    ref.invalidate(trashServiceProvider);
    ref.invalidate(announcementServiceProvider);
    ref.invalidate(userServiceProvider);
    ref.invalidate(userControllerProvider);
    ref.invalidate(dashboardServiceProvider);
    ref.invalidate(receiptServiceProvider);
    ref.invalidate(imageServiceProvider);

    // ── Stateful / cached providers ──
    // These hold cached UI state derived from the database. After a
    // restore the underlying data has changed, so they must be
    // invalidated to force a fresh load on next access.
    ref.invalidate(dashboardProvider);
    ref.invalidate(cartProvider);
    ref.invalidate(paymentSettingsProvider);
    ref.invalidate(authStateProvider);
    ref.invalidate(aiAdvisorChatProvider);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y · h:mm a').format(date.toLocal());
  }

  /// Logs a debug message with the full exception and stack trace. In
  /// debug/development mode this prints to the console so the actual
  /// failure is visible during development. In release builds it is a
  /// no-op so users never see raw stack traces.
  void _log(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[BackupRestoreScreen] $message: $error\n$stackTrace');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Scaffold(
      appBar: const AppHeader(
        title: 'Backup & Restore',
        showBackButton: true,
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading backup history...')
          : _loadError != null
              ? ErrorState(
                  title: 'Unable to Load Backup Data',
                  message: _loadError,
                  onRetry: _loadBackups,
                )
              : RefreshIndicator(
                  onRefresh: _loadBackups,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 800 : double.infinity,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Backup & Restore',
                            style: AppTypography.headlineSmallSemibold(context),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Protect your business data and recover it when needed.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: Spacing.xxl),

                          _buildLocationCard(context),
                          const SizedBox(height: Spacing.xxl),

                          _buildSectionHeader(context, 'Quick Actions'),
                          const SizedBox(height: Spacing.md),
                          _buildQuickActions(context, isTablet),
                          const SizedBox(height: Spacing.xxl),

                          _buildSectionHeader(context, 'Recent Backups'),
                          const SizedBox(height: Spacing.md),
                          if (_backups.isEmpty)
                            EmptyState(
                              icon: Icons.cloud_off_outlined,
                              title: 'No Backups Yet',
                              message:
                                  'Create your first backup to protect your Pinoy POS data.',
                              action: FilledButton.icon(
                                onPressed:
                                    _isExporting ? null : _exportBackup,
                                icon: const Icon(Icons.upload_outlined),
                                label: const Text('Export Backup'),
                              ),
                            )
                          else
                            _buildBackupList(context, isTablet),

                          const SizedBox(height: Spacing.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  // ── Location / Destination Status Card ───────────────────────────────

  Widget _buildLocationCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final backupService = ref.read(backupServiceProvider);
    final isWeb = kIsWeb;

    if (_locationLoading) {
      return AppCard(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 24, color: cs.primary),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Checking backup location...',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    final hasLocation = _backupLocation != null && !_backupLocation!.isNone;

    // On web, folder selection is not available; the browser handles the
    // download. Do not show a non-functional "Choose Backup Folder" button.
    if (isWeb) {
      return AppCard(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_outlined, size: 24, color: cs.primary),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Backup Destination',
                  style: AppTypography.titleMediumBold(context),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Backups are downloaded by your browser.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'You can choose the save location in the browser download dialog.',
              style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 24, color: cs.primary),
              const SizedBox(width: Spacing.sm),
              Text(
                'Backup Destination',
                style: AppTypography.titleMediumBold(context),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),

          if (hasLocation) ...[
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: AppSemanticColors.resolve(
                      AppSemanticColors.success, theme.brightness),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Backups will be saved here automatically.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_open, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      backupService.getDisplayLocation(_backupLocation),
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSelectingLocation ? null : _chooseBackupLocation,
                icon: _isSelectingLocation
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.edit_location_alt_outlined),
                label: Text(
                  _isSelectingLocation ? 'Opening picker...' : 'Change Location',
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'No backup location selected.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Choose a location before creating your first backup.',
              style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSelectingLocation ? null : _chooseBackupLocation,
                icon: _isSelectingLocation
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(
                  _isSelectingLocation
                      ? 'Opening picker...'
                      : 'Choose Backup Location',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section Header ───────────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: AppTypography.titleLargeBold(context),
    );
  }

  // ── Quick Actions ────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context, bool isTablet) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final actions = [
      _QuickActionCard(
        icon: Icons.upload_outlined,
        title: 'Export Backup',
        subtitle: 'Create and save a copy of your data',
        iconColor: cs.primary,
        isLoading: _isExporting,
        onTap: _isExporting ? null : _exportBackup,
      ),
      _QuickActionCard(
        icon: Icons.download_outlined,
        title: 'Import Backup',
        subtitle: 'Restore from a previously exported file',
        iconColor: cs.tertiary,
        isLoading: _isImporting,
        onTap: _isImporting ? null : _importBackup,
      ),
    ];

    if (isTablet) {
      return Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: actions[0],
            ),
          ),
          Expanded(child: actions[1]),
        ],
      );
    }

    return Column(
      children: actions
          .map((a) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: a,
              ))
          .toList(),
    );
  }

  // ── Backup List ──────────────────────────────────────────────────────

  Widget _buildBackupList(BuildContext context, bool isTablet) {
    final sorted = List<BackupHistory>.from(_backups)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: sorted.map((backup) => _buildBackupCard(context, backup)).toList(),
    );
  }

  Widget _buildBackupCard(BuildContext context, BackupHistory backup) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final display = _displayCache[backup.id];
    final fileName = display?.name ?? 'backup.db';
    final location = display?.location ?? '';

    return AppCard(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: AppTypography.titleMediumSemibold(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (value) {
                  switch (value) {
                    case 'restore':
                      _restoreFromHistory(backup);
                    case 'delete':
                      _deleteBackup(backup);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(
                      children: [
                        Icon(Icons.restore_outlined, size: 20),
                        SizedBox(width: Spacing.sm),
                        Text('Restore'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: cs.error),
                        const SizedBox(width: Spacing.sm),
                        Text('Delete', style: TextStyle(color: cs.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              Text(
                _formatFileSize(backup.fileSize),
                style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: Spacing.md),
              Icon(Icons.schedule, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              Flexible(
                child: Text(
                  _formatDate(backup.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupDisplay {
  final String name;
  final String location;

  const _BackupDisplay({
    required this.name,
    required this.location,
  });
}

// ── Quick Action Card Widget ────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isLoading;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(Spacing.lg),
      onTap: isLoading ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isLoading)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: iconColor,
                  ),
                )
              else
                Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMediumSemibold(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
