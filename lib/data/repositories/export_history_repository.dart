import 'package:pinoy_pos/data/dao/export_history_dao.dart';
import 'package:pinoy_pos/data/models/export_history.dart';

class ExportHistoryRepository {
  final ExportHistoryDao _exportHistoryDao = ExportHistoryDao();

  Future<int> insert(ExportHistory exportHistory) => _exportHistoryDao.insert(exportHistory);
  Future<List<ExportHistory>> getAll() => _exportHistoryDao.getAll();
  Future<List<ExportHistory>> getAllActive() => _exportHistoryDao.getAllActive();
}
