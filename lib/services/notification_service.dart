import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/notification.dart';
import 'package:pinoy_pos/data/repositories/notification_repository.dart';
import 'package:sqflite/sqflite.dart';

class NotificationService {
  final NotificationRepository _notificationRepository = NotificationRepository();
  final SessionManager _sessionManager = SessionManager();

  Future<List<Notification>> getNotifications() async {
    if (_sessionManager.currentUser == null) {
      return [];
    }
    return _notificationRepository.getByUserId(_sessionManager.currentUser!.id!);
  }

  Future<List<Notification>> getUnreadNotifications() async {
    if (_sessionManager.currentUser == null) {
      return [];
    }
    return _notificationRepository.getUnreadByUserId(_sessionManager.currentUser!.id!);
  }

  Future<int> getUnreadCount() async {
    if (_sessionManager.currentUser == null) {
      return 0;
    }
    return _notificationRepository.getUnreadCount(_sessionManager.currentUser!.id!);
  }

  Future<void> createNotification({
    required String title,
    required String message,
    String? type,
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final notification = Notification(
      title: title,
      message: message,
      type: type,
      userId: userId ?? _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    );
    await _notificationRepository.insert(notification, txn: txn);
  }

  /// Creates a notification for each user in [userIds].
  ///
  /// Used when an event (e.g. an announcement) should be delivered to
  /// multiple recipients. Each user receives their own notification row
  /// so that read/unread state is per-user.
  Future<void> createNotificationForUsers({
    required String title,
    required String message,
    String? type,
    required List<int> userIds,
    DatabaseExecutor? txn,
  }) async {
    final now = DateTime.now();
    for (final userId in userIds) {
      final notification = Notification(
        title: title,
        message: message,
        type: type,
        userId: userId,
        createdAt: now,
      );
      await _notificationRepository.insert(notification, txn: txn);
    }
  }

  /// Checks whether an unread notification of the given [type] already
  /// exists for the given [userId] with the exact same [title] and
  /// [message].
  ///
  /// Used for low-stock deduplication: once a LOW_STOCK notification has
  /// been created for a product, subsequent stock changes that keep the
  /// product below the threshold should NOT create duplicate
  /// notifications. The check is scoped to unread notifications so that
  /// once a user reads and acknowledges the alert, a new low-stock event
  /// (e.g. stock drops further) can generate a fresh notification.
  Future<bool> hasUnreadNotification({
    required int userId,
    required String type,
    required String title,
    required String message,
    DatabaseExecutor? txn,
  }) async {
    return _notificationRepository.hasUnreadNotification(
      userId: userId,
      type: type,
      title: title,
      message: message,
      txn: txn,
    );
  }

  /// Marks a single notification as read. The notification must belong to
  /// the current user; the DAO enforces `user_id = ?` so a user cannot
  /// mutate another user's notification even if the id is known.
  Future<void> markAsRead(int id) async {
    if (_sessionManager.currentUser == null) {
      return;
    }
    await _notificationRepository.markAsRead(
      id,
      _sessionManager.currentUser!.id!,
    );
  }

  Future<void> markAllAsRead() async {
    if (_sessionManager.currentUser == null) {
      return;
    }
    await _notificationRepository.markAllAsRead(_sessionManager.currentUser!.id!);
  }
}
