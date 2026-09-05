import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';

class AnnouncementService {
  final AnnouncementRepository _announcementRepository = AnnouncementRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final NotificationService _notificationService = NotificationService();
  final UserRepository _userRepository = UserRepository();

  Future<List<Announcement>> getActiveAnnouncements() async {
    if (!_sessionManager.hasPermission('view_announcements')) {
      return [];
    }
    return _announcementRepository.getActiveAnnouncements();
  }

  Future<List<Announcement>> getPinnedAnnouncements() async {
    if (!_sessionManager.hasPermission('view_announcements')) {
      return [];
    }
    return _announcementRepository.getPinnedAnnouncements();
  }

  Future<List<Announcement>> getAllAnnouncements() async {
    if (!_sessionManager.hasPermission('manage_announcements')) {
      return [];
    }
    return _announcementRepository.getAllActive();
  }

  /// Creates a new announcement and notifies all active Staff users.
  ///
  /// Notifications are created AFTER the announcement is persisted so
  /// that a notification failure does not prevent the announcement from
  /// being saved. Each Staff user receives their own notification row
  /// so that read/unread state is per-user.
  Future<bool> createAnnouncement({
    required String title,
    required String content,
    bool isPinned = false,
    DateTime? expiresAt,
  }) async {
    if (!_sessionManager.hasPermission('manage_announcements')) {
      throw AuthorizationException('manage_announcements');
    }

    if (title.isEmpty || content.isEmpty) {
      return false;
    }

    final announcement = Announcement(
      title: title,
      content: content,
      isPinned: isPinned,
      expiresAt: expiresAt,
      createdBy: _sessionManager.currentUser?.id,
      createdAt: DateTime.now(),
    );

    await _announcementRepository.insert(announcement);
    await _activityLogService.logActivity(
      action: 'create_announcement',
      entity: 'announcement',
      details: 'Created announcement: $title',
    );

    // Notify all active Staff users about the new announcement.
    // Owner and Admin do not receive announcement notifications because
    // the Owner is the one creating them and Admin does not have access
    // to announcements.
    await _notifyStaffOfNewAnnouncement(title, content);

    return true;
  }

  /// Creates a "New Announcement" notification for every active Staff
  /// user. The notification carries the full announcement content because
  /// Staff cannot open the Announcements screen (no `view_announcements`
  /// permission) — this notification is their only way to read it.
  /// Failures are swallowed so that a notification issue never
  /// prevents the announcement from being created.
  Future<void> _notifyStaffOfNewAnnouncement(
    String title,
    String content,
  ) async {
    try {
      final staffUsers = await _userRepository.getByRole(UserRole.staff);
      final activeStaffIds = staffUsers
          .where((u) => u.isActive && u.id != null)
          .map((u) => u.id!)
          .toList();

      if (activeStaffIds.isEmpty) return;

      await _notificationService.createNotificationForUsers(
        title: 'New Announcement: $title',
        message: content,
        type: 'announcement',
        userIds: activeStaffIds,
      );
    } catch (_) {
      // Notification creation is best-effort. Do not fail the
      // announcement creation if notifications cannot be sent.
    }
  }

  Future<bool> updateAnnouncement(Announcement announcement) async {
    if (!_sessionManager.hasPermission('manage_announcements')) {
      throw AuthorizationException('manage_announcements');
    }

    if (announcement.title.isEmpty || announcement.content.isEmpty) {
      return false;
    }

    await _announcementRepository.update(announcement);
    await _activityLogService.logActivity(
      action: 'update_announcement',
      entity: 'announcement',
      entityId: announcement.id,
      details: 'Updated announcement: ${announcement.title}',
    );
    return true;
  }

  Future<bool> deleteAnnouncement(int id) async {
    if (!_sessionManager.hasPermission('manage_announcements')) {
      throw AuthorizationException('manage_announcements');
    }

    await _announcementRepository.softDelete(id);
    await _activityLogService.logActivity(
      action: 'delete_announcement',
      entity: 'announcement',
      entityId: id,
      details: 'Soft-deleted announcement',
    );
    return true;
  }

  Future<bool> togglePin(int id, bool isPinned) async {
    if (!_sessionManager.hasPermission('manage_announcements')) {
      throw AuthorizationException('manage_announcements');
    }

    final announcement = await _announcementRepository.getById(id);
    if (announcement == null) return false;

    await _announcementRepository.update(
      announcement.copyWith(isPinned: isPinned),
    );
    return true;
  }
}
