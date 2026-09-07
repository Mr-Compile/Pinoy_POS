import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/announcement_dao.dart';
import 'package:pinoy_pos/data/models/announcement.dart';

class AnnouncementRepository {
  final AnnouncementDao _announcementDao = AnnouncementDao();

  Future<int> insert(Announcement announcement, {DatabaseExecutor? txn}) =>
      _announcementDao.insert(announcement, txn: txn);
  Future<int> update(Announcement announcement, {DatabaseExecutor? txn}) =>
      _announcementDao.update(announcement, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _announcementDao.delete(id, txn: txn);
  Future<int> softDelete(int id, {DatabaseExecutor? txn}) =>
      _announcementDao.softDelete(id, txn: txn);
  Future<int> restore(int id, {DatabaseExecutor? txn}) =>
      _announcementDao.restore(id, txn: txn);
  Future<Announcement?> getById(int id, {DatabaseExecutor? txn}) =>
      _announcementDao.getById(id, txn: txn);
  Future<List<Announcement>> getAll({DatabaseExecutor? txn}) =>
      _announcementDao.getAll(txn: txn);
  Future<List<Announcement>> getAllActive({DatabaseExecutor? txn}) =>
      _announcementDao.getAllActive(txn: txn);
  Future<List<Announcement>> getDeleted({DatabaseExecutor? txn}) =>
      _announcementDao.getDeleted(txn: txn);
  Future<List<Announcement>> getActiveAnnouncements() =>
      _announcementDao.getActiveAnnouncements();
  Future<List<Announcement>> getPinnedAnnouncements() =>
      _announcementDao.getPinnedAnnouncements();
}
