import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/backup_history.dart';

class BackupHistoryDao extends BaseDao<BackupHistory> {
  @override
  String get tableName => 'backup_history';

  @override
  BackupHistory fromMap(Map<String, dynamic> map) => BackupHistory.fromMap(map);
}
