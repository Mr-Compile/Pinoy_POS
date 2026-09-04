import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/data/dao/attachment_dao.dart';
import 'package:pinoy_pos/data/models/attachment.dart';

class AttachmentRepository {
  final AttachmentDao _attachmentDao = AttachmentDao();

  Future<int> insert(Attachment attachment, {DatabaseExecutor? txn}) =>
      _attachmentDao.insert(attachment, txn: txn);

  Future<int> update(Attachment attachment, {DatabaseExecutor? txn}) =>
      _attachmentDao.update(attachment, txn: txn);

  Future<int> delete(int id, {DatabaseExecutor? txn}) =>
      _attachmentDao.delete(id, txn: txn);

  Future<Attachment?> getById(int id, {DatabaseExecutor? txn}) =>
      _attachmentDao.getById(id, txn: txn);

  Future<List<Attachment>> getByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.getByEntity(entityType, entityId, txn: txn);

  Future<List<Attachment>> getActiveByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.getActiveByEntity(entityType, entityId, txn: txn);

  Future<List<Attachment>> getDeletedByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.getDeletedByEntity(entityType, entityId, txn: txn);

  Future<int> softDeleteByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.softDeleteByEntity(entityType, entityId, txn: txn);

  Future<int> restoreByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.restoreByEntity(entityType, entityId, txn: txn);

  Future<int> deleteByEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.deleteByEntity(entityType, entityId, txn: txn);

  Future<List<Attachment>> getByAttachmentType(
    String entityType,
    int entityId,
    String attachmentType, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentDao.getByAttachmentType(
          entityType, entityId, attachmentType, txn: txn);
}
