import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/date_time_utils.dart';
import 'package:pinoy_pos/core/notification_style.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/notification.dart' as models;
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_square.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _NotificationFilter { all, unread, alerts, announcements }

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<models.Notification> _notifications = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  _NotificationFilter _selectedFilter = _NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final notificationService = ref.read(notificationServiceProvider);
      final notifications = await notificationService.getNotifications();

      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to load notifications.',
        );
      }
    }
  }

  Future<void> _markAsRead(models.Notification notification) async {
    if (notification.isRead) return;

    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.markAsRead(notification.id!);
      refreshNotificationCount(ref);
      _loadNotifications();
    } catch (e) {
      if (mounted) {
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to mark notification as read.',
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() => _isProcessing = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.markAllAsRead();
      refreshNotificationCount(ref);
      if (mounted) {
        await AppDialogService.success(
          context,
          title: 'Done',
          message: 'All notifications marked as read.',
        );
      }
      _loadNotifications();
    } catch (e) {
      if (mounted) {
        AppDialogService.error(
          context,
          title: 'Error',
          message: 'Failed to mark all notifications as read.',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<models.Notification> _filteredNotifications() {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return _notifications.where((n) {
      final category =
          NotificationStyle.fromType(n.type, cs, brightness).category;

      switch (_selectedFilter) {
        case _NotificationFilter.all:
          return true;
        case _NotificationFilter.unread:
          return !n.isRead;
        case _NotificationFilter.alerts:
          return category == NotificationCategory.alert;
        case _NotificationFilter.announcements:
          return category == NotificationCategory.announcement;
      }
    }).toList();
  }

  Map<String, List<models.Notification>> _groupNotifications(
    List<models.Notification> notifications,
  ) {
    final now = DateTime.now();
    final groups = <String, List<models.Notification>>{};

    for (final n in notifications) {
      String key;
      if (DateUtils.isSameDay(n.createdAt, now)) {
        key = 'Today';
      } else if (DateUtils.isSameDay(
        n.createdAt,
        now.subtract(const Duration(days: 1)),
      )) {
        key = 'Yesterday';
      } else {
        key = 'Earlier';
      }
      groups.putIfAbsent(key, () => []).add(n);
    }

    final ordered = <String, List<models.Notification>>{};
    for (final k in const ['Today', 'Yesterday', 'Earlier']) {
      if (groups.containsKey(k)) {
        ordered[k] = groups[k]!;
      }
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Notifications',
          showBackButton: true,
          showNotificationBell: false,
        ),
        body: const LoadingState(message: 'Loading notifications...'),
      );
    }

    final filtered = _filteredNotifications();
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppHeader(
        title: 'Notifications',
        showBackButton: true,
        showNotificationBell: false,
        actions: [
          if (hasUnread)
            IconButton(
              icon: _isProcessing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).appBarTheme.foregroundColor,
                      ),
                    )
                  : const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: _isProcessing ? null : _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: filtered.isEmpty
          ? _buildEmptyState()
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                _buildFilterChips(),
                const SizedBox(height: Spacing.md),
                ..._buildSectionedList(filtered),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    String title;
    String message;

    switch (_selectedFilter) {
      case _NotificationFilter.unread:
        title = 'No Unread Notifications';
        message = 'You\'re all caught up!';
        break;
      case _NotificationFilter.alerts:
        title = 'No Alerts';
        message = 'There are no alerts right now.';
        break;
      case _NotificationFilter.announcements:
        title = 'No Announcements';
        message = 'There are no announcements right now.';
        break;
      case _NotificationFilter.all:
        title = 'No Notifications';
        message =
            'You\'re all caught up! New alerts and announcements will appear here.';
        break;
    }

    return EmptyState(
      icon: Icons.notifications_none,
      title: title,
      message: message,
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        _buildFilterChip(_NotificationFilter.all, 'All'),
        _buildFilterChip(_NotificationFilter.unread, 'Unread'),
        _buildFilterChip(_NotificationFilter.alerts, 'Alerts'),
        _buildFilterChip(_NotificationFilter.announcements, 'Announcements'),
      ],
    );
  }

  Widget _buildFilterChip(_NotificationFilter filter, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedFilter == filter;

    return RawMaterialButton(
      onPressed: () {
        setState(() {
          _selectedFilter = isSelected ? _NotificationFilter.all : filter;
        });
      },
      elevation: 0,
      fillColor: isSelected ? cs.primary : cs.surface,
      splashColor: cs.onPrimary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outline,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium(context).copyWith(
          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _buildSectionedList(List<models.Notification> notifications) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groupNotifications(notifications);
    final widgets = <Widget>[];

    for (final entry in groups.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: AppCard(
            variant: AppCardVariant.filled,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSectionTitle(entry.key, cs),
                ..._buildSectionRows(entry.value, cs),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: AppTypography.labelMedium(context).copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSectionRows(
    List<models.Notification> notifications,
    ColorScheme cs,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < notifications.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, color: cs.outline));
      }
      rows.add(_NotificationRow(
        notification: notifications[i],
        onTap: () => _markAsRead(notifications[i]),
      ));
    }
    return rows;
  }
}

class _NotificationRow extends StatelessWidget {
  final models.Notification notification;
  final VoidCallback onTap;

  const _NotificationRow({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final style = NotificationStyle.fromType(
      notification.type,
      cs,
      brightness,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: notification.isRead
            ? const EdgeInsets.all(14)
            : const EdgeInsets.fromLTRB(11, 14, 14, 14),
        decoration: BoxDecoration(
          border: notification.isRead
              ? null
              : Border(
                  left: BorderSide(
                    color: cs.error,
                    width: 3,
                  ),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconSquare(
              icon: style.icon,
              size: 38,
              backgroundColor: style.color.withValues(alpha: 0.16),
              iconColor: style.color,
              iconSizeFactor: 0.5,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: AppTypography.titleSmallBold(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.message,
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateTimeUtils.formatRelative(notification.createdAt),
                    style: AppTypography.labelSmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            notification.isRead
                ? const SizedBox(width: 8, height: 8)
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
