import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/announcement.dart';

class AnnouncementDao extends BaseDao<Announcement> {
  @override
  String get tableName => 'announcements';

  @override
  Announcement fromMap(Map<String, dynamic> map) => Announcement.fromMap(map);

  Future<List<Announcement>> getActiveAnnouncements() async {
    final database = await db;
    final maps = await database.rawQuery('''
      SELECT * FROM announcements
      WHERE deleted_at IS NULL
      AND (expires_at IS NULL OR expires_at > datetime('now'))
      ORDER BY is_pinned DESC, created_at DESC
    ''');
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Announcement>> getPinnedAnnouncements() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'is_pinned = 1 AND deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
