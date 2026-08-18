import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/export_history.dart';

class ExportHistoryDao extends BaseDao<ExportHistory> {
  @override
  String get tableName => 'export_history';

  @override
  ExportHistory fromMap(Map<String, dynamic> map) => ExportHistory.fromMap(map);
}
