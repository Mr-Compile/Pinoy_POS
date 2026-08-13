import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final AnnouncementRepository _announcementRepository = AnnouncementRepository();
  List<Announcement> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    final announcements = await _announcementRepository.getActiveAnnouncements();
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
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await EnhancedDialogs.showDeleteDialog(
      context: context,
      itemName: announcement.title,
    );

    if (confirmed == true && mounted) {
      try {
        await _announcementRepository.softDelete(announcement.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'Announcement deleted successfully');
          _loadAnnouncements();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to delete announcement');
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
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
                  final data = Announcement(
                    id: announcement?.id,
                    title: titleController.text.trim(),
                    content: contentController.text.trim(),
                    isPinned: isPinned,
                    createdBy: announcement?.createdBy,
                    createdAt: announcement?.createdAt ?? DateTime.now(),
                  );
                  if (announcement == null) {
                    await _announcementRepository.insert(data);
                  } else {
                    await _announcementRepository.update(data);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    showSuccessSnackbar(context, 'Announcement saved successfully');
                    _loadAnnouncements();
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorSnackbar(context, 'Failed to save announcement');
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
