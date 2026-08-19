import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  List<Announcement> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    // Load through the Riverpod service provider so the UI never accesses
    // the repository or DAO directly (UI -> Provider -> Service ->
    // Repository -> DAO -> SQLite).
    final announcementService = ref.read(announcementServiceProvider);
    final announcements = await announcementService.getActiveAnnouncements();
    if (mounted) {
      setState(() {
        _announcements = announcements;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAnnouncement(Announcement announcement) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_announcements')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: announcement.title,
    );

    if (confirmed == true && mounted) {
      try {
        final announcementService = ref.read(announcementServiceProvider);
        final success =
            await announcementService.deleteAnnouncement(announcement.id!);
        if (mounted) {
          if (success) {
            await AppDialogService.success(context, title: 'Deleted', message: 'Announcement deleted successfully.');
            _loadAnnouncements();
          } else {
            AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to delete announcement.');
          }
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to delete announcement.');
        }
      }
    }
  }

  Future<void> _togglePin(Announcement announcement) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_announcements')) {
      AppDialogService.accessDenied(context);
      return;
    }

    try {
      final announcementService = ref.read(announcementServiceProvider);
      final success = await announcementService.togglePin(
        announcement.id!,
        !announcement.isPinned,
      );
      if (mounted) {
        if (success) {
          _loadAnnouncements();
        } else {
          AppDialogService.error(context, title: 'Error', message: 'Failed to update pin status.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Error', message: 'Failed to update pin status.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManage = authNotifier.hasPermission('manage_announcements');
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Announcements',
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    // Primary create action. On tablet/desktop a visible labeled
    // FilledButton.icon is placed in the AppBar; on mobile a FAB.extended
    // is used so the action is always reachable and clearly labeled.
    final Widget? createAction = canManage
        ? (isTablet
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.campaign),
                  label: const Text('Add Announcement'),
                  onPressed: () => _showAnnouncementDialog(),
                ),
              )
            : null)
        : null;

    return Scaffold(
      appBar: AppHeader(
        title: 'Announcements',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnnouncements,
          ),
          ?createAction,
        ],
      ),
      floatingActionButton: canManage && !isTablet
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.campaign),
              label: const Text('Add Announcement'),
              onPressed: () => _showAnnouncementDialog(),
            )
          : null,
      body: _announcements.isEmpty
          ? EmptyState(
              icon: Icons.campaign,
              title: 'No Announcements Yet',
              message: 'Create an announcement to share updates with your team.',
              // No create button here — the FAB (mobile) / AppBar
              // action (tablet) is the single primary create action.
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _announcements.length,
              itemBuilder: (context, index) {
                final announcement = _announcements[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (announcement.isPinned)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.push_pin, size: 16),
                            ),
                          Expanded(
                            child: Text(
                              announcement.title,
                              style: AppTypography.titleMediumBold(context),
                            ),
                          ),
                          if (canManage) ...[
                            IconButton(
                              icon: Icon(
                                announcement.isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 20,
                              ),
                              tooltip: announcement.isPinned ? 'Unpin' : 'Pin',
                              onPressed: () => _togglePin(announcement),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit',
                              onPressed: () => _showAnnouncementDialog(announcement: announcement),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Delete',
                              onPressed: () => _deleteAnnouncement(announcement),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(announcement.content),
                      const SizedBox(height: 8),
                      Text(
                        announcement.createdAt.toLocal().toString().split('.')[0],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showAnnouncementDialog({Announcement? announcement}) {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: announcement?.title ?? '');
    final contentController = TextEditingController(text: announcement?.content ?? '');
    bool isPinned = announcement?.isPinned ?? false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(announcement == null ? 'Add Announcement' : 'Edit Announcement'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    validator: (value) => Validators.required(value, 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: 'Content',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    validator: (value) => Validators.required(value, 'Content'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Pin to top'),
                    value: isPinned,
                    onChanged: (value) => setState(() => isPinned = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                try {
                  final announcementService =
                      ref.read(announcementServiceProvider);
                  bool success;
                  if (announcement == null) {
                    success = await announcementService.createAnnouncement(
                      title: titleController.text.trim(),
                      content: contentController.text.trim(),
                      isPinned: isPinned,
                    );
                  } else {
                    final data = announcement.copyWith(
                      title: titleController.text.trim(),
                      content: contentController.text.trim(),
                      isPinned: isPinned,
                    );
                    success =
                        await announcementService.updateAnnouncement(data);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    if (success) {
                      await AppDialogService.success(context, title: 'Saved', message: 'Announcement saved successfully.');
                      _loadAnnouncements();
                    } else {
                      AppDialogService.error(context, title: 'Save Failed', message: 'Failed to save announcement.');
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppDialogService.error(context, title: 'Save Failed', message: 'Failed to save announcement.');
                  }
                } finally {
                  if (context.mounted) setState(() => isSaving = false);
                }
              },
              label: 'Save',
            ),
          ],
        ),
      ),
    );
  }
}
