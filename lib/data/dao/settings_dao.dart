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

  /// Returns the raw `groq_api_key` column for one-time migration to secure
  /// storage. Returns null when the column is absent, empty, or missing on a
  /// pre-v5 / damaged database (the query would throw `no such column`).
  Future<String?> getGroqApiKeyRaw() async {
    try {
      final database = await db;
      final maps = await database.query(
        tableName,
        columns: ['groq_api_key'],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      final value = maps.first['groq_api_key'];
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }
}
