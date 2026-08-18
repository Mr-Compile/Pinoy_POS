import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class AnnouncementService {
  final AnnouncementRepository _announcementRepository = AnnouncementRepository();
  final AuthService _authService = AuthService();

  Future<List<Announcement>> getActiveAnnouncements() async {
    return _announcementRepository.getActiveAnnouncements();
  }

  Future<List<Announcement>> getPinnedAnnouncements() async {
    return _announcementRepository.getPinnedAnnouncements();
  }

  Future<List<Announcement>> getAllAnnouncements() async {
    if (!_authService.hasPermission('manage_users')) {
      return [];
    }
    return _announcementRepository.getAllActive();
  }

  Future<bool> createAnnouncement({
    required String title,
    required String content,
    bool isPinned = false,
    DateTime? expiresAt,
  }) async {
    if (!_authService.hasPermission('manage_users')) {
      return false;
    }

    if (title.isEmpty || content.isEmpty) {
      return false;
    }

    final announcement = Announcement(
      title: title,
      content: content,
      isPinned: isPinned,
      expiresAt: expiresAt,
      createdBy: _authService.currentUser?.id,
      createdAt: DateTime.now(),
    );

    await _announcementRepository.insert(announcement);
    return true;
  }

  Future<bool> updateAnnouncement(Announcement announcement) async {
    if (!_authService.hasPermission('manage_users')) {
      return false;
    }

    if (announcement.title.isEmpty || announcement.content.isEmpty) {
      return false;
    }

    await _announcementRepository.update(announcement);
    return true;
  }

  Future<bool> deleteAnnouncement(int id) async {
    if (!_authService.hasPermission('manage_users')) {
      return false;
    }

    await _announcementRepository.softDelete(id);
    return true;
  }

  Future<bool> togglePin(int id, bool isPinned) async {
    if (!_authService.hasPermission('manage_users')) {
      return false;
    }

    final announcement = await _announcementRepository.getById(id);
    if (announcement == null) return false;

    await _announcementRepository.update(
      announcement.copyWith(isPinned: isPinned),
    );
    return true;
  }
}
