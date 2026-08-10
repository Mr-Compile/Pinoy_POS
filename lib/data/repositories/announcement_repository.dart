import 'package:pinoy_pos/data/dao/announcement_dao.dart';
import 'package:pinoy_pos/data/models/announcement.dart';

class AnnouncementRepository {
  final AnnouncementDao _announcementDao = AnnouncementDao();

  Future<int> insert(Announcement announcement) => _announcementDao.insert(announcement);
  Future<int> update(Announcement announcement) => _announcementDao.update(announcement);
  Future<int> delete(int id) => _announcementDao.delete(id);
  Future<int> softDelete(int id) => _announcementDao.softDelete(id);
  Future<int> restore(int id) => _announcementDao.restore(id);
  Future<Announcement?> getById(int id) => _announcementDao.getById(id);
  Future<List<Announcement>> getAll() => _announcementDao.getAll();
  Future<List<Announcement>> getAllActive() => _announcementDao.getAllActive();
  Future<List<Announcement>> getDeleted() => _announcementDao.getDeleted();
  Future<List<Announcement>> getActiveAnnouncements() => _announcementDao.getActiveAnnouncements();
  Future<List<Announcement>> getPinnedAnnouncements() => _announcementDao.getPinnedAnnouncements();
}
