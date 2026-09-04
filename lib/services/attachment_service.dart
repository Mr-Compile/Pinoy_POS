import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/data/models/attachment.dart';
import 'package:pinoy_pos/data/repositories/attachment_repository.dart';
import 'package:pinoy_pos/services/file_storage_service.dart';
import 'package:pinoy_pos/services/image_service.dart';

/// Central service for generic file attachments.
///
/// Attachments follow the entity lifecycle:
///   - Added when a file is associated with an entity.
///   - Soft-deleted when the parent entity is soft-deleted.
///   - Restored when the parent entity is restored.
///   - Permanently deleted (row + physical file) when the parent entity is
///     permanently deleted.
///
/// The service is entity-agnostic: the caller supplies `entity_type` and
/// `entity_id`. It reuses [ImageService] for images and [FileStorageService]
/// for other files.
class AttachmentService {
  final AttachmentRepository _attachmentRepository = AttachmentRepository();
  final ImageService _imageService = ImageService();
  final FileStorageService _fileStorageService = FileStorageService();

  /// Records an attachment for a file that is already stored.
  ///
  /// If [mimeType] is omitted, it is detected from the file bytes/name.
  /// Returns the persisted [Attachment] or null if the file could not be read.
  Future<Attachment?> addAttachment({
    required String entityType,
    required int entityId,
    required String relativePath,
    String? fileName,
    String? mimeType,
    String? attachmentType,
    DatabaseExecutor? txn,
  }) async {
    try {
      final resolvedName = fileName ?? p.basename(relativePath);
      final resolvedMime =
          mimeType ?? await _detectMime(relativePath, resolvedName);

      final attachment = Attachment(
        entityType: entityType,
        entityId: entityId,
        filePath: relativePath,
        mimeType: resolvedMime,
        fileName: resolvedName,
        attachmentType: attachmentType,
        createdAt: DateTime.now(),
      );

      final id = await _attachmentRepository.insert(attachment, txn: txn);
      return attachment.copyWith(id: id);
    } catch (e) {
      return null;
    }
  }

  /// Picks an image from the gallery/camera, stores it, and records it as an
  /// attachment for the given entity.
  Future<Attachment?> pickAndAddImage({
    required String entityType,
    required int entityId,
    String? attachmentType,
  }) async {
    final result = await _imageService.pickAndStoreImage();
    if (!result.isSuccess || result.filePath == null) return null;

    return addAttachment(
      entityType: entityType,
      entityId: entityId,
      relativePath: result.filePath!,
      fileName: _fileNameFromPath(result.filePath!),
      mimeType: result.mediaType,
      attachmentType: attachmentType,
    );
  }

  /// Picks a non-image file, stores it, and records it as an attachment.
  Future<Attachment?> pickAndAddFile({
    required String entityType,
    required int entityId,
    List<String>? allowedExtensions,
    String? attachmentType,
  }) async {
    final result = await _fileStorageService.pickAndStoreFile(
      allowedExtensions: allowedExtensions,
    );
    if (!result.isSuccess || result.filePath == null) return null;

    return addAttachment(
      entityType: entityType,
      entityId: entityId,
      relativePath: result.filePath!,
      fileName: _fileNameFromPath(result.filePath!),
      mimeType: result.mimeType,
      attachmentType: attachmentType,
    );
  }

  Future<List<Attachment>> getAttachments(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentRepository.getByEntity(entityType, entityId, txn: txn);

  Future<List<Attachment>> getActiveAttachments(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentRepository.getActiveByEntity(entityType, entityId, txn: txn);

  Future<List<Attachment>> getDeletedAttachments(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentRepository.getDeletedByEntity(entityType, entityId, txn: txn);

  /// Returns the most recent active primary-image attachment for an entity.
  Future<Attachment?> getPrimaryImageAttachment(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
    String attachmentType = 'primary_image',
  }) async {
    final attachments = await _attachmentRepository.getByAttachmentType(
      entityType,
      entityId,
      attachmentType,
      txn: txn,
    );
    if (attachments.isEmpty) return null;
    return attachments.first;
  }

  /// Soft-deletes all active attachments for an entity.
  Future<int> softDeleteAttachmentsForEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentRepository.softDeleteByEntity(entityType, entityId, txn: txn);

  /// Restores all soft-deleted attachments for an entity.
  Future<int> restoreAttachmentsForEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) =>
      _attachmentRepository.restoreByEntity(entityType, entityId, txn: txn);

  /// Permanently deletes attachment rows and physical files for an entity.
  ///
  /// If [txn] is provided, only the database rows are deleted inside the
  /// transaction and the physical files are returned so the caller can delete
  /// them after the transaction commits. Otherwise both rows and files are
  /// deleted in this call.
  Future<List<String>> permanentDeleteAttachmentsForEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
    bool deleteFiles = true,
  }) async {
    final attachments =
        await _attachmentRepository.getByEntity(entityType, entityId, txn: txn);
    final filePaths = attachments.map((a) => a.filePath).toList();

    if (attachments.isNotEmpty) {
      await _attachmentRepository.deleteByEntity(entityType, entityId,
          txn: txn);
    }

    if (deleteFiles) {
      await _fileStorageService.deleteFiles(filePaths);
    }

    return filePaths;
  }

  /// Deletes the attachment row whose [filePath] matches the entity.
  ///
  /// Also deletes the physical file if [deleteFile] is true.
  Future<int> deleteAttachmentByPath(
    String entityType,
    int entityId,
    String? relativePath, {
    DatabaseExecutor? txn,
    bool deleteFile = true,
  }) async {
    if (relativePath == null || relativePath.isEmpty) return 0;

    final count = await _attachmentRepository.getByEntity(entityType, entityId,
            txn: txn)
        .then((list) async {
      final match = list.where((a) => a.filePath == relativePath).toList();
      if (match.isEmpty) return 0;

      var total = 0;
      for (final attachment in match) {
        if (attachment.id != null) {
          total += await _attachmentRepository.delete(attachment.id!, txn: txn);
        }
      }
      return total;
    });

    if (deleteFile) {
      await _fileStorageService.deleteFile(relativePath);
    }

    return count;
  }

  /// Replaces the primary image attachment for an entity and deletes the old
  /// file.
  Future<Attachment?> replacePrimaryImage(
    String entityType,
    int entityId,
    String? newRelativePath,
    String? newMimeType, {
    DatabaseExecutor? txn,
    String attachmentType = 'primary_image',
  }) async {
    final oldAttachments = await _attachmentRepository.getByAttachmentType(
      entityType,
      entityId,
      attachmentType,
      txn: txn,
    );

    if (newRelativePath == null || newRelativePath.isEmpty) {
      // No new image: remove the existing primary image attachments.
      for (final a in oldAttachments) {
        if (a.id != null) {
          await _attachmentRepository.delete(a.id!, txn: txn);
        }
        await _fileStorageService.deleteFile(a.filePath);
      }
      return null;
    }

    final fileName = _fileNameFromPath(newRelativePath);
    final mimeType = newMimeType ?? await _detectMime(newRelativePath, fileName);

    // Delete old primary attachments.
    for (final a in oldAttachments) {
      if (a.id != null) {
        await _attachmentRepository.delete(a.id!, txn: txn);
      }
      await _fileStorageService.deleteFile(a.filePath);
    }

    final attachment = Attachment(
      entityType: entityType,
      entityId: entityId,
      filePath: newRelativePath,
      mimeType: mimeType,
      fileName: fileName,
      attachmentType: attachmentType,
      createdAt: DateTime.now(),
    );

    final id = await _attachmentRepository.insert(attachment, txn: txn);
    return attachment.copyWith(id: id);
  }

  /// Deletes a physical file without touching the attachment table.
  ///
  /// Use this for legacy paths or cleanup after callers have already managed
  /// the database rows.
  Future<void> deletePhysicalFile(String? relativePath) async {
    await _fileStorageService.deleteFile(relativePath);
  }

  Future<void> deletePhysicalFiles(List<String> relativePaths) async {
    await _fileStorageService.deleteFiles(relativePaths);
  }

  Future<String> _detectMime(String relativePath, String fileName) async {
    final file = await _fileStorageService.resolveFile(relativePath) ??
        await _imageService.resolveImageFile(relativePath);
    Uint8List? bytes;
    if (file != null) {
      try {
        bytes = await file.readAsBytes();
      } catch (_) {}
    }
    final fileType = FileTypeUtils.detectFromNameAndBytes(fileName, bytes);
    return fileType?.mime ?? 'application/octet-stream';
  }

  String _fileNameFromPath(String relativePath) {
    return p.basename(relativePath);
  }
}
