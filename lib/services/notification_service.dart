import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/notification.dart';
import 'package:pinoy_pos/data/repositories/notification_repository.dart';

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
  }) async {
    final notification = Notification(
      title: title,
      message: message,
      type: type,
      userId: userId ?? _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    );
    await _notificationRepository.insert(notification);
  }

  Future<void> markAsRead(int id) async {
    await _notificationRepository.markAsRead(id);
  }

  Future<void> markAllAsRead() async {
    if (_sessionManager.currentUser == null) {
      return;
    }
    await _notificationRepository.markAllAsRead(_sessionManager.currentUser!.id!);
  }
}
