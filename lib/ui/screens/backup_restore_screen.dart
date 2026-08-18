import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  List<BackupHistory> _backups = [];
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showErrorSnackbar(context, 'Failed to load backup history');
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _isBackingUp = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      await backupService.createBackup();
      if (mounted) {
        showSuccessSnackbar(context, 'Backup created successfully');
        _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to create backup: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }

  Future<void> _restoreBackup(BackupHistory backup) async {
    final confirmed = await EnhancedDialogs.showRestoreBackupDialog(
      context: context,
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final success = await backupService.restoreBackup(backup.filePath);
      if (mounted) {
        if (success) {
          showSuccessSnackbar(context, 'Backup restored successfully. Please restart the app.');
        } else {
          showErrorSnackbar(context, 'Failed to restore backup. File may be corrupt or missing.');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to restore backup: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _deleteBackup(BackupHistory backup) async {
    final confirmed = await EnhancedDialogs.showPermanentDeleteDialog(
      context: context,
    );

    if (confirmed != true || !mounted) return;

    try {
      final backupService = ref.read(backupServiceProvider);
      final success = await backupService.deleteBackup(backup.id!, backup.filePath);
      if (mounted) {
        if (success) {
          showSuccessSnackbar(context, 'Backup deleted successfully');
          _loadBackups();
        } else {
          showErrorSnackbar(context, 'Failed to delete backup');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to delete backup');
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState()
          : _isRestoring
              ? const LoadingState(message: 'Restoring backup...')
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.backup, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Create Backup',
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      Text(
                                        'Save a copy of your database',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isBackingUp ? null : _createBackup,
                                icon: _isBackingUp
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.cloud_upload),
                                label: Text(_isBackingUp ? 'Creating...' : 'Create Backup'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Backup History',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      if (_backups.isEmpty)
                        const EmptyState(
                          icon: Icons.history,
                          title: 'No Backups',
                          message: 'Created backups will appear here',
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            return AppCard(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: const Icon(Icons.backup_table),
                                title: Text(
                                  backup.filePath.split('/').last,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_formatFileSize(backup.fileSize)} • ${backup.createdAt.toLocal().toString().split('.')[0]}',
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'restore') {
                                      _restoreBackup(backup);
                                    } else if (value == 'delete') {
                                      _deleteBackup(backup);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'restore',
                                      child: Row(
                                        children: [
                                          Icon(Icons.restore),
                                          SizedBox(width: 8),
                                          Text('Restore'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                          const SizedBox(width: 8),
                                          Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }
}
