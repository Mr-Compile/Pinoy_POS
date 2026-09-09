import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
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
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';
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

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Announcements',
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    final createAction = canManage
        ? ResponsiveCreateAction(
            label: 'Add Announcement',
            icon: Icons.add,
            onPressed: _showAnnouncementDialog,
          )
        : null;

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;

    return Scaffold(
      appBar: const AppHeader(
        title: 'Announcements',
        showBackButton: true,
      ),
      floatingActionButton: createFab,
      body: Column(
        children: [
          CrudToolbar(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            pinnedControls: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loadAnnouncements,
              ),
            ],
            primaryAction: toolbarAction,
          ),
          Expanded(
            child: _announcements.isEmpty
                ? EmptyState(
                    icon: Icons.campaign,
                    title: 'No Announcements Yet',
                    message:
                        'Create an announcement to share updates with your team.',
                    // No create button here — the FAB (mobile portrait) /
                    // toolbar action (other layouts) is the single primary
                    // create action.
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomClearance),
              itemCount: _announcements.length,
              itemBuilder: (context, index) {
                final announcement = _announcements[index];
                final cs = Theme.of(context).colorScheme;
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  onTap: () => _showAnnouncementDetails(announcement),
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
                            AppIconButton(
                              icon: announcement.isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              size: 20,
                              selected: announcement.isPinned,
                              tooltip: announcement.isPinned
                                  ? 'Unpin announcement'
                                  : 'Pin announcement',
                              onPressed: () => _togglePin(announcement),
                            ),
                            AppIconButton(
                              icon: Icons.edit_outlined,
                              size: 20,
                              tooltip: 'Edit announcement',
                              onPressed: () => _showAnnouncementDialog(
                                  announcement: announcement),
                            ),
                            AppIconButton(
                              icon: Icons.delete_outline,
                              size: 20,
                              color: cs.error,
                              tooltip: 'Delete announcement',
                              onPressed: () =>
                                  _deleteAnnouncement(announcement),
                            ),
                          ],
                          AppIconButton(
                            icon: Icons.visibility_outlined,
                            size: 20,
                            tooltip: 'View announcement',
                            onPressed: () =>
                                _showAnnouncementDetails(announcement),
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
          ),
        ],
      ),
    );
  }

  /// Read-only detail view for an announcement (the View action).
  Future<void> _showAnnouncementDetails(Announcement announcement) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialog(
        type: AppDialogType.info,
        title: announcement.title,
        message: announcement.content,
        details: [
          'Posted: ${announcement.createdAt.toLocal().toString().split('.')[0]}',
          if (announcement.isPinned) 'Pinned to top',
          if (announcement.expiresAt != null)
            'Expires: ${announcement.expiresAt!.toLocal().toString().split(' ')[0]}',
        ].join('\n'),
        showClose: true,
        actions: [
          AppDialogAction(
            label: 'Close',
            isPrimary: true,
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _showAnnouncementDialog({Announcement? announcement}) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: announcement == null ? AppDialogType.add : AppDialogType.edit,
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

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextFormField(
                  controller: titleController,
                  label: 'Title',
                  prefixIcon: Icons.subject,
                  validator: (value) => Validators.required(value, 'Title'),
                  onChanged: (_) => state.markChanged(),
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: contentController,
                  label: 'Content',
                  prefixIcon: Icons.message_outlined,
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
