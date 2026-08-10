import 'package:pinoy_pos/data/models/notification.dart';
import 'package:pinoy_pos/data/repositories\notification_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class NotificationService {
  final NotificationRepository _notificationRepository = NotificationRepository();
  final AuthService _authService = AuthService();

  Future<List<Notification>> getNotifications() async {
    if (_authService.currentUser == null) {
      return [];
    }
    return _notificationRepository.getByUserId(_authService.currentUser!.id!);
  }

  Future<List<Notification>> getUnreadNotifications() async {
    if (_authService.currentUser == null) {
      return [];
    }
    return _notificationRepository.getUnreadByUserId(_authService.currentUser!.id!);
  }

  Future<int> getUnreadCount() async {
    if (_authService.currentUser == null) {
      return 0;
    }
    return _notificationRepository.getUnreadCount(_authService.currentUser!.id!);
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
      userId: userId ?? _authService.currentUser?.id,
      createdAt: DateTime.now(),
    );
    await _notificationRepository.insert(notification);
  }

  Future<void> markAsRead(int id) async {
    await _notificationRepository.markAsRead(id);
  }

  Future<void> markAllAsRead() async {
    if (_authService.currentUser == null) {
      return;
    }
    await _notificationRepository.markAllAsRead(_authService.currentUser!.id!);
  }
}
