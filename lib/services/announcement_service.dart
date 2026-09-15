import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Returns the active pinned announcements for the dashboard banner.
  ///
  /// Unlike [getPinnedAnnouncements] this is NOT gated on
  /// `view_announcements`: the banner is how Staff and Admin receive
  /// announcement content (they have no access to the Announcements
  /// screen), and the same content is already pushed to them through
  /// notifications. Any authenticated user may read it.
  Future<List<Announcement>> getBannerAnnouncements() async {
    if (!_sessionManager.isAuthenticated) {
      return [];
    }
    return _announcementRepository.getPinnedAnnouncements();
  }

  /// SharedPreferences key holding the banner-dismissed announcement ids
  /// for [userId]. Dismissal is per-user because several accounts share a
  /// device profile.
  static String _dismissedKey(int userId) =>
      'dismissed_announcement_ids_$userId';

  /// Returns the ids of pinned announcements the current user has
  /// dismissed from the dashboard banner.
  Future<Set<int>> getDismissedBannerIds() async {
    final userId = _sessionManager.currentUser?.id;
    if (userId == null) return {};
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dismissedKey(userId)) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  /// Marks [announcementId] as dismissed for the current user so the
  /// dashboard banner no longer shows it. The banner resurfaces only if
  /// the announcement is repinned under a new id or a different pinned
  /// announcement exists.
  Future<void> dismissBannerAnnouncement(int announcementId) async {
    final userId = _sessionManager.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_dismissedKey(userId)) ?? [];
    final key = announcementId.toString();
    if (!ids.contains(key)) {
      ids.add(key);
      await prefs.setStringList(_dismissedKey(userId), ids);
    }
  }

  /// Creates a new announcement and notifies all active Staff and Admin
  /// users.
  ///
  /// Notifications are created AFTER the announcement is persisted so
  /// that a notification failure does not prevent the announcement from
  /// being saved. Each recipient receives their own notification row
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

    // Notify all active Staff and Admin users about the new
    // announcement. The Owner does not receive one because they are the
    // author.
    await _notifyUsersOfNewAnnouncement(title, content);

    return true;
  }

  /// Creates a "New Announcement" notification for every active Staff
  /// and Admin user. The notification carries the full announcement
  /// content because neither role can open the Announcements screen
  /// (no `view_announcements` permission) — this notification is their
  /// only way to read it.
  /// Failures are swallowed so that a notification issue never
  /// prevents the announcement from being created.
  Future<void> _notifyUsersOfNewAnnouncement(
    String title,
    String content,
  ) async {
    try {
      final staffUsers = await _userRepository.getByRole(UserRole.staff);
      final adminUsers = await _userRepository.getByRole(UserRole.admin);
      final recipientIds = [...staffUsers, ...adminUsers]
          .where((u) => u.isActive && u.id != null)
          .map((u) => u.id!)
          .toList();

      if (recipientIds.isEmpty) return;

      await _notificationService.createNotificationForUsers(
        title: 'New Announcement: $title',
        message: content,
        type: 'announcement',
        userIds: recipientIds,
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

    final announcement = await _announcementRepository.getById(id);
    if (announcement == null) return false;

    final result = await TrashService().moveToTrash(
      entityType: 'announcement',
      entityId: id,
      entityName: announcement.title,
      snapshotJson: TrashService.snapshotForAnnouncement(announcement),
    );

    return result.success;
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
