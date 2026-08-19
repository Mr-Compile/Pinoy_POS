import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/service_providers.dart';

/// Provider that fetches the current user's unread notification count.
///
/// Use [notificationCountProvider] to read the count and
/// [refreshNotificationCount] to invalidate it after a notification is
/// marked as read.
final notificationCountProvider = FutureProvider<int>((ref) async {
  final notificationService = ref.read(notificationServiceProvider);
  return notificationService.getUnreadCount();
});

/// Invalidates the notification count so the next read re-fetches from
/// the database. Call this after marking notifications as read.
void refreshNotificationCount(WidgetRef ref) {
  ref.invalidate(notificationCountProvider);
}
