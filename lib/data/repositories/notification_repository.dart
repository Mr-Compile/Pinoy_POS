import 'package:pinoy_pos/data/dao/notification_dao.dart';
import 'package:pinoy_pos/data/models/notification.dart';
import 'package:sqflite/sqflite.dart';

class NotificationRepository {
  final NotificationDao _notificationDao = NotificationDao();

  Future<int> insert(Notification notification, {DatabaseExecutor? txn}) => _notificationDao.insert(notification, txn: txn);
  Future<int> update(Notification notification) => _notificationDao.update(notification);
  Future<int> delete(int id) => _notificationDao.delete(id);
  Future<Notification?> getById(int id) => _notificationDao.getById(id);
  Future<List<Notification>> getAll() => _notificationDao.getAll();
  Future<List<Notification>> getByUserId(int userId) => _notificationDao.getByUserId(userId);
  Future<List<Notification>> getUnreadByUserId(int userId) => _notificationDao.getUnreadByUserId(userId);
  Future<int> getUnreadCount(int userId) => _notificationDao.getUnreadCount(userId);
  Future<void> markAsRead(int id) => _notificationDao.markAsRead(id);
  Future<void> markAllAsRead(int userId) => _notificationDao.markAllAsRead(userId);
}
