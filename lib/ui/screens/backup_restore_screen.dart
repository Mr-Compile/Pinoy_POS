import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Backup & Restore screen — Admin only.
///
/// Architecture: UI → backupServiceProvider → BackupService → DAO → SQLite
///
/// The screen never touches DAOs or SQLite directly. All operations go
/// through [BackupService] which enforces the `backup_restore` permission.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  List<BackupHistory> _backups = [];
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _loadError;
  String _defaultLocation = '';

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadDefaultLocation();
  }

  Future<void> _loadDefaultLocation() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (mounted) {
        setState(() {
          _defaultLocation = appDir.path;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _defaultLocation = 'App Documents';
        });
      }
    }
  }

  String _getDisplayLocation(String path) {
    final dir = p.dirname(path);
    final parts = p.split(dir);
    if (parts.length <= 3) return parts.join(' › ');
    return '... › ${parts.sublist(parts.length - 3).join(' › ')}';
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final backups = await backupService.getBackupHistory();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load backup history. Please try again.';
        });
      }
    }
  }

  // ── Export Backup ────────────────────────────────────────────────────

  Future<void> _exportBackup() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.exportBackup();

      if (!mounted) return;

      switch (result.result) {
        case BackupExportResult.success:
          final location = backupService.getDisplayLocation(result.path!);
          await AppDialogService.backupExportSuccess(
            context,
            displayName: result.displayName!,
            location: location,
          );
          await _loadBackups();
        case BackupExportResult.canceled:
          // User canceled — no dialog needed
          break;
        case BackupExportResult.failed:
          await AppDialogService.backupExportFailed(context);
      }
    } catch (_) {
      if (mounted) {
        await AppDialogService.backupExportFailed(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
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
          // Invalidate all service providers so cached state is discarded
          _invalidateAllProviders();
          await AppDialogService.backupRestoreSuccess(context);
          await _loadBackups();
        case BackupImportResult.canceled:
          // User canceled — no dialog
          break;
        case BackupImportResult.invalidFile:
          await AppDialogService.invalidBackupFile(context);
        case BackupImportResult.incompatible:
          await AppDialogService.incompatibleBackupFile(context);
        case BackupImportResult.failed:
          await AppDialogService.backupRestoreFailed(context);
      }
    } catch (_) {
      if (mounted) {
        await AppDialogService.backupRestoreFailed(context);
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

    final confirmed = await AppDialogService.restoreBackupConfirm(
      context,
      displayName: backup.filePath.split('/').last,
      fileSize: _formatFileSize(backup.fileSize),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.restoreFromPath(backup.filePath);

      if (!mounted) return;

      switch (result) {
        case BackupImportResult.success:
          _invalidateAllProviders();
          await AppDialogService.backupRestoreSuccess(context);
          await _loadBackups();
        case BackupImportResult.invalidFile:
          await AppDialogService.invalidBackupFile(context);
        case BackupImportResult.incompatible:
          await AppDialogService.incompatibleBackupFile(context);
        case BackupImportResult.failed:
          await AppDialogService.backupRestoreFailed(context);
        case BackupImportResult.canceled:
          break;
      }
    } catch (_) {
      if (mounted) {
        await AppDialogService.backupRestoreFailed(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // ── Delete Backup ────────────────────────────────────────────────────

  Future<void> _deleteBackup(BackupHistory backup) async {
    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: backup.filePath.split('/').last,
    );

    if (confirmed != true || !mounted) return;

    try {
      final backupService = ref.read(backupServiceProvider);
      final success = await backupService.deleteBackup(backup.id!, backup.filePath);
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
    } catch (_) {
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
    ref.invalidate(trashServiceProvider);
    ref.invalidate(announcementServiceProvider);
    ref.invalidate(userServiceProvider);
    ref.invalidate(userControllerProvider);
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

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Scaffold(
      appBar: AppHeader(
        title: 'Backup & Restore',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadBackups,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState()
          : _loadError != null
              ? ErrorState(
                  title: 'Failed to Load Backups',
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
                          // ── Page subtitle ──
                          Text(
                            'Protect and recover your Pinoy POS data.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: Spacing.xxl),

                          // ── Data Protection status card ──
                          _buildStatusCard(context),
                          const SizedBox(height: Spacing.xxl),

                          // ── Quick Actions ──
                          _buildSectionHeader(context, 'Quick Actions'),
                          const SizedBox(height: Spacing.md),
                          _buildQuickActions(context, isTablet),
                          const SizedBox(height: Spacing.xxl),

                          // ── Recent Backups ──
                          _buildSectionHeader(context, 'Recent Backups'),
                          const SizedBox(height: Spacing.md),
                          if (_backups.isEmpty)
                            EmptyState(
                              icon: Icons.cloud_off_outlined,
                              title: 'No Backups Yet',
                              message: 'Create your first backup to protect your Pinoy POS data.',
                              action: FilledButton.icon(
                                onPressed: _isExporting ? null : _exportBackup,
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

  // ── Status Card ──────────────────────────────────────────────────────

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final sortedBackups = List<BackupHistory>.from(_backups)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final actualLatest = sortedBackups.isNotEmpty ? sortedBackups.first : null;
    final hasBackup = actualLatest != null;

    return AppCard(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 24,
                color: cs.primary,
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                'Data Protection',
                style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          if (hasBackup) ...[
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: AppSemanticColors.success,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Last backup: ${_formatDate(actualLatest.createdAt)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Size: ${_formatFileSize(actualLatest.fileSize)}',
              style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'No backup has been created yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.lg),
          // Default backup location info
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default backup location:',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    if (_defaultLocation.isNotEmpty)
                      Text(
                        _getDisplayLocation(_defaultLocation),
                        style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'You can choose a different location each time you export.',
            style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: Spacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isExporting ? null : _exportBackup,
              icon: _isExporting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimary,
                      ),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(_isExporting ? 'Creating Backup...' : 'Export Backup'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ───────────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
    final backupService = ref.read(backupServiceProvider);
    final fileName = backupService.getDisplayName(backup.filePath);
    final location = backupService.getDisplayLocation(backup.filePath);

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
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
