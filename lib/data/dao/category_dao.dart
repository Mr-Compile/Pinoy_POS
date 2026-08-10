import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/category.dart';

class CategoryDao extends BaseDao<Category> {
  @override
  String get tableName => 'categories';

  @override
  Category fromMap(Map<String, dynamic> map) => Category.fromMap(map);

  Future<Category?> getByName(String name) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'name = ? AND deleted_at IS NULL',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  Future<List<Category>> getActiveCategories() async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'is_active = 1 AND deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
