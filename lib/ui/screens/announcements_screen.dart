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

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManage = authNotifier.hasPermission('manage_announcements');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Announcements')),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnnouncements,
          ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAnnouncementDialog(),
            ),
        ],
      ),
      body: _announcements.isEmpty
          ? const EmptyState(
              icon: Icons.campaign,
              title: 'No Announcements',
              message: 'Announcements will appear here',
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
                          if (canManage)
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteAnnouncement(announcement),
                            ),
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
