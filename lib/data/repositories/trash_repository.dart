import 'package:pinoy_pos/data/dao/trash_dao.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';

class TrashRepository {
  final TrashDao _trashDao = TrashDao();

  Future<int> insert(TrashItem trashItem) => _trashDao.insert(trashItem);
  Future<int> delete(int id) => _trashDao.delete(id);
  Future<int> deleteByEntity(String entityType, int entityId) => _trashDao.deleteByEntity(entityType, entityId);
  Future<List<TrashItem>> getAll() => _trashDao.getAll();
  Future<List<TrashItem>> getByEntityType(String entityType) => _trashDao.getByEntityType(entityType);
  Future<TrashItem?> getByEntity(String entityType, int entityId) => _trashDao.getByEntity(entityType, entityId);
}
