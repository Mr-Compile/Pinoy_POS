import 'package:pinoy_pos/data/dao/backup_history_dao.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';

class BackupHistoryRepository {
  final BackupHistoryDao _backupHistoryDao = BackupHistoryDao();

  Future<int> insert(BackupHistory backupHistory) => _backupHistoryDao.insert(backupHistory);
  Future<int> delete(int id) => _backupHistoryDao.delete(id);
  Future<List<BackupHistory>> getAll() => _backupHistoryDao.getAll();
  Future<List<BackupHistory>> getAllActive() => _backupHistoryDao.getAllActive();
}
