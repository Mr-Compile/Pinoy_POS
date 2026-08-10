import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/settings.dart';

class SettingsDao extends BaseDao<Settings> {
  @override
  String get tableName => 'settings';

  @override
  Settings fromMap(Map<String, dynamic> map) => Settings.fromMap(map);

  Future<Settings?> getSettings() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }
}
