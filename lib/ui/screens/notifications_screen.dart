import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/notification.dart' as models;
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<models.Notification> _notifications = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    final notificationService = ref.read(notificationServiceProvider);
    final notifications = await notificationService.getNotifications();

    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(models.Notification notification) async {
    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.markAsRead(notification.id!);
      _loadNotifications();
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Error', message: 'Failed to mark notification as read.');
      }
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() => _isProcessing = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.markAllAsRead();
      if (mounted) {
        await AppDialogService.success(context, title: 'Done', message: 'All notifications marked as read.');
      }
      _loadNotifications();
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Error', message: 'Failed to mark all notifications as read.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
        ),
        body: const LoadingState(),
      );
    }

    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            IconButton(
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: _isProcessing ? null : _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: _notifications.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'No Notifications',
              message: 'You\'re all caught up!',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(notification.title),
                    subtitle: Text(notification.message),
                    trailing: notification.isRead
                        ? null
                        : Icon(Icons.circle,
                            color: Theme.of(context).colorScheme.primary, size: 8),
                    onTap: notification.isRead ? null : () => _markAsRead(notification),
                  ),
                );
              },
            ),
    );
  }
}
