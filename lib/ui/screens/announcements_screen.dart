import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';

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

  Future<void> _showAnnouncementDialog({Announcement? announcement}) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: announcement == null ? 'Add Announcement' : 'Edit Announcement',
        childBuilder: (context, state) {
          final titleController = state.textController(
            'title',
            text: announcement?.title ?? '',
          );
          final contentController = state.textController(
            'content',
            text: announcement?.content ?? '',
          );
          final isPinned =
              state.value<bool>('isPinned', announcement?.isPinned ?? false) ??
                  false;

          return SingleChildScrollView(
            child: Form(
              key: state.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextFormField(
                    controller: titleController,
                    label: 'Title',
                    validator: (value) => Validators.required(value, 'Title'),
                    onChanged: (_) => state.markChanged(),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: contentController,
                    label: 'Content',
                    maxLines: 4,
                    validator: (value) => Validators.required(value, 'Content'),
                    onChanged: (_) => state.markChanged(),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Pin to top'),
                    value: isPinned,
                    onChanged: (value) =>
                        state.setValue<bool>('isPinned', value),
                  ),
                ],
              ),
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) async {
              if (state.hasChanges) {
                final discard = await AppDialogService.unsavedChanges(context);
                if (discard == true && context.mounted) {
                  state.pop(const ModalResult<void>.cancelled());
                }
              } else if (context.mounted) {
                state.pop(const ModalResult<void>.cancelled());
              }
            },
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: (context) {
              if (state.isSaving) return;
              _saveAnnouncement(state, announcement, context);
            },
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result?.isSaved ?? false) {
      await AppDialogService.success(
        context,
        title: 'Saved',
        message: 'Announcement saved successfully.',
      );
      if (!mounted) return;
      refreshNotificationCount(ref);
      _loadAnnouncements();
    }
  }

  Future<void> _saveAnnouncement(
    AppDialogFormState<ModalResult<void>> state,
    Announcement? announcement,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) {
      return;
    }

    final title = state.textController('title').text.trim();
    final content = state.textController('content').text.trim();
    final isPinned = state.value<bool>('isPinned') ?? false;

    state.setSaving(true);

    try {
      final announcementService = ref.read(announcementServiceProvider);
      bool success;
      if (announcement == null) {
        success = await announcementService.createAnnouncement(
          title: title,
          content: content,
          isPinned: isPinned,
        );
      } else {
        final data = announcement.copyWith(
          title: title,
          content: content,
          isPinned: isPinned,
        );
        success = await announcementService.updateAnnouncement(data);
      }

      if (success) {
        state.pop(const ModalResult<void>.saved());
      } else {
        if (dialogContext.mounted) {
          state.setSaving(false);
          await AppDialogService.error(
            dialogContext,
            title: 'Save Failed',
            message: 'Failed to save announcement.',
          );
        }
      }
    } catch (e) {
      if (dialogContext.mounted) {
        state.setSaving(false);
        await AppDialogService.error(
          dialogContext,
          title: 'Save Failed',
          message: 'Failed to save announcement.',
        );
      }
    }
  }
}
