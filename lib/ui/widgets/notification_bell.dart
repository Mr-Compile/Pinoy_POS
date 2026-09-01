import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/safe_navigation.dart';
import 'package:pinoy_pos/data/models/notification.dart' as models;
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/notifications_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';

/// Notification bell with unread badge.
///
/// On tablet/desktop (width >= 600): taps open a popover dropdown showing
/// recent notifications. On mobile: taps navigate to the full
/// [NotificationsScreen].
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final GlobalKey _iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final countAsync = ref.watch(notificationCountProvider);
    final unreadCount = countAsync.maybeWhen(
      data: (count) => count,
      orElse: () => 0,
    );

    return IconButton(
      key: _iconKey,
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppSemanticColors.error,
        label: Text(
          _formatBadge(unreadCount),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppSemanticColors.onError,
          ),
        ),
        child: const Icon(Icons.notifications_outlined),
      ),
      tooltip: 'Notifications',
      onPressed: () => _onTap(unreadCount),
    );
  }

  void _onTap(int unreadCount) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 600) {
      _showDropdown();
    } else {
      _safePush(const NotificationsScreen());
    }
  }

  void _safePush(Widget screen) {
    SafeNavigator.pushUnique<void>(
      context,
      screen,
      onComplete: () => refreshNotificationCount(ref),
    );
  }

  void _showDropdown() {
    final renderBox = _iconKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<void>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width - 320,
        offset.dy + size.height + 8,
        offset.dx + size.width,
        0,
      ),
      constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _NotificationDropdownContent(
            onClosed: () => Navigator.of(context, rootNavigator: true).pop(),
            onViewAll: () {
              Navigator.of(context, rootNavigator: true).pop();
              _safePush(const NotificationsScreen());
            },
            onNotificationTapped: (notification) {
              Navigator.of(context, rootNavigator: true).pop();
              _handleNotificationTap(notification);
            },
          ),
        ),
      ],
    );
  }

  void _handleNotificationTap(models.Notification notification) async {
    // Mark as read
    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.markAsRead(notification.id!);
      refreshNotificationCount(ref);
    } catch (e, st) {
      debugPrint('[NotificationBell] Failed to mark notification as read: $e\n$st');
    }

    // Navigate based on type
    if (!mounted) return;
    final type = notification.type;
    Widget? target;
    switch (type) {
      case 'low_stock':
        target = const StockScreen();
        break;
      case 'announcement':
        target = const AnnouncementsScreen();
        break;
      case 'backup':
        target = const BackupRestoreScreen();
        break;
    }
    if (target != null) {
      SafeNavigator.pushUnique<void>(context, target);
    }
  }

  String _formatBadge(int count) {
    if (count > 99) return '99+';
    if (count > 9) return '9+';
    return count.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dropdown content
// ─────────────────────────────────────────────────────────────────────────

class _NotificationDropdownContent extends ConsumerStatefulWidget {
  final VoidCallback onClosed;
  final VoidCallback onViewAll;
  final ValueChanged<models.Notification> onNotificationTapped;

  const _NotificationDropdownContent({
    required this.onClosed,
    required this.onViewAll,
    required this.onNotificationTapped,
  });

  @override
  ConsumerState<_NotificationDropdownContent> createState() =>
      _NotificationDropdownContentState();
}

class _NotificationDropdownContentState
    extends ConsumerState<_NotificationDropdownContent> {
  List<models.Notification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final notificationService = ref.read(notificationServiceProvider);
    final notifications = await notificationService.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = notifications.take(8).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Notifications', style: AppTypography.titleMediumBold(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_notifications.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 40, color: colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('No notifications',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final n = _notifications[index];
                  return _NotificationTile(
                    notification: n,
                    onTap: () => widget.onNotificationTapped(n),
                  );
                },
              ),
            ),
          // Footer
          const Divider(height: 1),
          InkWell(
            onTap: widget.onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View all notifications',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Notification tile
// ─────────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final models.Notification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUnread = !notification.isRead;

    final iconData = _iconForType(notification.type);
    final iconColor = _colorForType(notification.type, colorScheme);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isUnread
            ? colorScheme.primary.withValues(alpha: 0.04)
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isUnread)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.circle,
                              size: 8, color: colorScheme.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.message,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'low_stock':
        return Icons.warning_amber_rounded;
      case 'announcement':
        return Icons.campaign_outlined;
      case 'backup':
        return Icons.backup_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _colorForType(String? type, ColorScheme cs) {
    switch (type) {
      case 'low_stock':
        return AppSemanticColors.warning;
      case 'announcement':
        return cs.primary;
      case 'backup':
        return AppSemanticColors.info;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _timeAgo(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
  }
}
