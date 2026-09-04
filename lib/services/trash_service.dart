import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/trash_operation_result.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/stock_history_repository.dart';
import 'package:pinoy_pos/data/repositories/trash_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/attachment_service.dart';
import 'package:pinoy_pos/services/file_storage_service.dart';

/// Central owner of the soft-delete / restore / permanent-delete lifecycle.
///
/// All entity deletion flows (product, category, user) must record a Trash
/// snapshot through this service. The Trash UI reads from here; restore and
/// permanent-delete actions must also go through here so that attachment
/// records and physical files stay consistent.
class TrashService {
  final TrashRepository _trashRepository = TrashRepository();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final UserRepository _userRepository = UserRepository();
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final StockHistoryRepository _stockHistoryRepository =
      StockHistoryRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final AttachmentService _attachmentService = AttachmentService();
  final FileStorageService _fileStorageService = FileStorageService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _entityProduct = 'product';
  static const String _entityCategory = 'category';
  static const String _entityUser = 'user';

  static const Duration _retentionPeriod = Duration(days: 30);

  /// Returns all visible trash items.
  Future<List<TrashItem>> getAllTrash() async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    final items = await _trashRepository.getAll();
    return _withDeletedByNames(items);
  }

  /// Returns trash items for a single entity type.
  Future<List<TrashItem>> getByEntityType(String entityType) async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }
    final items = await _trashRepository.getByEntityType(entityType);
    return _withDeletedByNames(items);
  }

  /// Searches trash by name within an optional entity-type filter.
  Future<List<TrashItem>> searchTrash({
    String? query,
    String? entityType,
  }) async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return [];
    }

    final where = <String>[];
    final whereArgs = <Object?>[];

    if (entityType != null && entityType != 'all') {
      where.add('entity_type = ?');
      whereArgs.add(entityType);
    }

    if (query != null && query.trim().isNotEmpty) {
      where.add('entity_name LIKE ?');
      whereArgs.add('%${query.trim()}%');
    }

    final whereClause = where.isEmpty ? null : where.join(' AND ');
    final items = await _trashRepository.getAll(
      where: whereClause,
      whereArgs: whereArgs,
    );
    return _withDeletedByNames(items);
  }

  /// Moves an entity to trash.
  ///
  /// The caller is responsible for ensuring the entity is not already in the
  /// trash. This method soft-deletes the source row, soft-deletes its
  /// attachments, and inserts a Trash record with a JSON snapshot.
  Future<TrashOperationResult> moveToTrash({
    required String entityType,
    required int entityId,
    required String entityName,
    required String snapshotJson,
  }) async {
    if (!_canDeleteEntity(entityType)) {
      throw AuthorizationException(_deletePermissionFor(entityType));
    }

    final (attachmentCount, totalSizeBytes) =
        await _attachmentMetricsForEntity(entityType, entityId, snapshotJson);

    final db = await _dbHelper.database;
    try {
      await db.transaction((txn) async {
        // Soft-delete the entity row.
        await _softDeleteEntity(entityType, entityId, txn: txn);

        // Soft-delete associated attachment records.
        await _attachmentService.softDeleteAttachmentsForEntity(
          entityType,
          entityId,
          txn: txn,
        );

        // Insert the trash record. If one already exists for this entity,
        // delete it first so we don't accumulate duplicates.
        final existing = await _trashRepository.getByEntity(
          entityType,
          entityId,
          txn: txn,
        );
        if (existing?.id != null) {
          await _trashRepository.delete(existing!.id!, txn: txn);
        }

        final trash = TrashItem(
          entityType: entityType,
          entityId: entityId,
          entityName: entityName,
          snapshotJson: snapshotJson,
          deletedBy: _sessionManager.currentUser?.id,
          deletedAt: DateTime.now(),
          expiresAt: DateTime.now().add(_retentionPeriod),
          attachmentCount: attachmentCount,
          totalSizeBytes: totalSizeBytes,
        );
        await _trashRepository.insert(trash, txn: txn);
      });

      await _activityLogService.logActivity(
        action: 'move_to_trash',
        entity: entityType,
        entityId: entityId,
        details: 'Moved $entityType to trash: $entityName',
      );

      return const TrashOperationResult(success: true);
    } catch (e) {
      return TrashOperationResult(
        success: false,
        message: 'Failed to move $entityName to trash: $e',
      );
    }
  }

  /// Restores an entity from trash by [trashId].
  Future<TrashOperationResult> restoreFromTrash(int trashId) async {
    final trash = await _trashRepository.getById(trashId);
    if (trash == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Trash item not found',
      );
    }

    final entityType = trash.entityType;
    final entityId = trash.entityId;

    if (!_sessionManager.hasPermission('restore_trash')) {
      throw AuthorizationException('restore_trash');
    }
    if (!_sessionManager.hasPermission(_viewPermissionFor(entityType))) {
      throw AuthorizationException(_viewPermissionFor(entityType));
    }

    // Type-specific validation.
    final validation = await _validateRestore(entityType, entityId, trash);
    if (!validation.success) return validation;

    final db = await _dbHelper.database;
    try {
      await db.transaction((txn) async {
        await _restoreEntity(entityType, entityId, txn: txn);
        await _attachmentService.restoreAttachmentsForEntity(
          entityType,
          entityId,
          txn: txn,
        );
        await _trashRepository.delete(trashId, txn: txn);
      });

      await _activityLogService.logActivity(
        action: 'restore_from_trash',
        entity: entityType,
        entityId: entityId,
        details: 'Restored ${trash.entityName} from trash',
      );

      return const TrashOperationResult(success: true);
    } catch (e) {
      return TrashOperationResult(
        success: false,
        message: 'Failed to restore ${trash.entityName}: $e',
      );
    }
  }

  /// Restores an entity by [entityType] and [entityId].
  Future<TrashOperationResult> restoreByEntity(
    String entityType,
    int entityId,
  ) async {
    final trash = await _trashRepository.getByEntity(entityType, entityId);
    if (trash == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Trash record not found',
      );
    }
    return restoreFromTrash(trash.id!);
  }

  /// Permanently deletes an entity by [trashId].
  Future<TrashOperationResult> permanentDelete(int trashId) async {
    final trash = await _trashRepository.getById(trashId);
    if (trash == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Trash item not found',
      );
    }

    if (!_sessionManager.hasPermission(_deletePermissionFor(trash.entityType))) {
      throw AuthorizationException(_deletePermissionFor(trash.entityType));
    }

    return _permanentlyDeleteTrashItem(trash, checkPermissions: true);
  }

  /// Permanently deletes an entity by [entityType] and [entityId].
  Future<TrashOperationResult> permanentDeleteByEntity(
    String entityType,
    int entityId,
  ) async {
    final trash = await _trashRepository.getByEntity(entityType, entityId);
    if (trash == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Trash record not found',
      );
    }
    return permanentDelete(trash.id!);
  }

  /// Permanently deletes the entity represented by [trash].
  ///
  /// When [checkPermissions] is true the caller must have the delete
  /// permission for the entity type. When false (used by automatic
  /// cleanup) the deletion proceeds without a permission check, but the
  /// entity is still validated as soft-deleted.
  Future<TrashOperationResult> _permanentlyDeleteTrashItem(
    TrashItem trash, {
    bool checkPermissions = true,
  }) async {
    final entityType = trash.entityType;
    final entityId = trash.entityId;
    final trashId = trash.id;

    if (checkPermissions &&
        !_sessionManager.hasPermission(_deletePermissionFor(entityType))) {
      throw AuthorizationException(_deletePermissionFor(entityType));
    }

    final validation = await _validatePermanentDelete(
      entityType,
      entityId,
      trash,
    );
    if (!validation.success) return validation;

    // Capture file paths before the transaction removes the attachment rows.
    final attachmentPaths =
        await _attachmentService.getAttachments(entityType, entityId)
            .then((list) => list.map((a) => a.filePath).toList());
    final legacyPaths = await _legacyPathsForEntity(entityType, entityId);
    final allPaths = {...attachmentPaths, ...legacyPaths}.toList();

    final db = await _dbHelper.database;
    try {
      await db.transaction((txn) async {
        // Remove attachment rows (physical files are deleted after commit).
        await _attachmentService.permanentDeleteAttachmentsForEntity(
          entityType,
          entityId,
          txn: txn,
          deleteFiles: false,
        );

        // Handle dependent records before deleting the entity.
        await _clearEntityDependencies(entityType, entityId, txn: txn);

        // Hard-delete the source row.
        await _hardDeleteEntity(entityType, entityId, txn: txn);

        // Remove the trash record.
        if (trashId != null) {
          await _trashRepository.delete(trashId, txn: txn);
        }
      });

      // Delete physical files best-effort after the DB transaction commits.
      for (final path in allPaths) {
        await _attachmentService.deletePhysicalFile(path);
      }

      await _activityLogService.logActivity(
        action: 'permanently_delete',
        entity: entityType,
        entityId: entityId,
        details: 'Permanently deleted ${trash.entityName}',
      );

      return const TrashOperationResult(success: true);
    } on DatabaseException catch (e) {
      if (_isForeignKeyViolation(e)) {
        return const TrashOperationResult(
          success: false,
          message: 'This record is linked to other data and cannot be '
              'permanently deleted.',
        );
      }
      return TrashOperationResult(
        success: false,
        message: 'Failed to permanently delete ${trash.entityName}: $e',
      );
    } catch (e) {
      return TrashOperationResult(
        success: false,
        message: 'Failed to permanently delete ${trash.entityName}: $e',
      );
    }
  }

  /// Empties the trash by permanently deleting every trash item.
  Future<TrashOperationResult> emptyTrash() async {
    if (!_sessionManager.hasPermission('empty_trash')) {
      throw AuthorizationException('empty_trash');
    }

    final items = await _trashRepository.getAll();
    if (items.isEmpty) {
      return const TrashOperationResult(success: true);
    }

    final failed = <String>[];
    for (final item in items) {
      if (item.id == null) continue;
      final result = await permanentDelete(item.id!);
      if (!result.success) {
        failed.add(item.entityName ?? '${item.entityType} #${item.entityId}');
      }
    }

    if (failed.isNotEmpty) {
      return TrashOperationResult(
        success: false,
        message: 'Some items could not be deleted: ${failed.join(', ')}',
      );
    }

    return const TrashOperationResult(success: true);
  }

  /// Permanently deletes all expired trash items.
  ///
  /// This is a system cleanup operation and does not require user
  /// permissions, so it can run at app startup before a session exists.
  Future<int> processExpiredTrash() async {
    final expired = await _trashRepository.getExpired();

    var deleted = 0;
    for (final item in expired) {
      if (item.id == null) continue;
      final result = await _permanentlyDeleteTrashItem(
        item,
        checkPermissions: false,
      );
      if (result.success) deleted++;
    }
    return deleted;
  }

  /// Creates trash records for every soft-deleted product, category, or
  /// user that does not already have one.
  ///
  /// This is a system migration/backfill helper. It can run at startup
  /// before a session exists. The original entity's [deleted_at] is used
  /// for both the trash [deletedAt] and to compute [expiresAt].
  Future<int> backfillSoftDeletedToTrash() async {
    var count = 0;
    final now = DateTime.now();

    final products = await _productRepository.getDeleted();
    for (final product in products) {
      if (product.id == null) continue;
      final existing =
          await _trashRepository.getByEntity(_entityProduct, product.id!);
      if (existing != null) continue;

      final deletedAt = product.deletedAt ?? now;
      final trash = TrashItem(
        entityType: _entityProduct,
        entityId: product.id!,
        entityName: product.name,
        snapshotJson: jsonEncode(product.toMap()),
        deletedBy: _sessionManager.currentUser?.id,
        deletedAt: deletedAt,
        expiresAt: deletedAt.add(_retentionPeriod),
      );
      await _trashRepository.insert(trash);
      count++;
    }

    final categories = await _categoryRepository.getDeleted();
    for (final category in categories) {
      if (category.id == null) continue;
      final existing =
          await _trashRepository.getByEntity(_entityCategory, category.id!);
      if (existing != null) continue;

      final deletedAt = category.deletedAt ?? now;
      final trash = TrashItem(
        entityType: _entityCategory,
        entityId: category.id!,
        entityName: category.name,
        snapshotJson: jsonEncode(category.toMap()),
        deletedBy: _sessionManager.currentUser?.id,
        deletedAt: deletedAt,
        expiresAt: deletedAt.add(_retentionPeriod),
      );
      await _trashRepository.insert(trash);
      count++;
    }

    final users = await _userRepository.getDeleted();
    for (final user in users) {
      if (user.id == null) continue;
      final existing = await _trashRepository.getByEntity(_entityUser, user.id!);
      if (existing != null) continue;

      final deletedAt = user.deletedAt ?? now;
      final trash = TrashItem(
        entityType: _entityUser,
        entityId: user.id!,
        entityName: user.fullName,
        snapshotJson: snapshotForUser(user),
        deletedBy: _sessionManager.currentUser?.id,
        deletedAt: deletedAt,
        expiresAt: deletedAt.add(_retentionPeriod),
      );
      await _trashRepository.insert(trash);
      count++;
    }

    return count;
  }

  /// Restores multiple trash items by their trash ids.
  ///
  /// Continues on individual failures and returns a summary. The caller
  /// must already have permission to restore trash.
  Future<TrashOperationResult> bulkRestore(List<int> trashIds) async {
    if (!_sessionManager.hasPermission('restore_trash')) {
      throw AuthorizationException('restore_trash');
    }
    if (trashIds.isEmpty) {
      return const TrashOperationResult(
        success: false,
        message: 'No items selected',
      );
    }

    final failed = <String>[];
    for (final id in trashIds) {
      final result = await restoreFromTrash(id);
      if (!result.success) {
        final trash = await _trashRepository.getById(id);
        failed.add(trash?.entityName ?? 'Item #$id');
      }
    }

    if (failed.isEmpty) return const TrashOperationResult(success: true);
    return TrashOperationResult(
      success: false,
      message: 'Some items could not be restored: ${failed.join(', ')}',
    );
  }

  /// Permanently deletes multiple trash items by their trash ids.
  ///
  /// Continues on individual failures and returns a summary.
  Future<TrashOperationResult> bulkPermanentDelete(List<int> trashIds) async {
    if (trashIds.isEmpty) {
      return const TrashOperationResult(
        success: false,
        message: 'No items selected',
      );
    }

    final failed = <String>[];
    for (final id in trashIds) {
      final trash = await _trashRepository.getById(id);
      if (trash == null) continue;

      if (!_sessionManager.hasPermission(_deletePermissionFor(trash.entityType))) {
        failed.add(trash.entityName ?? 'Item #$id');
        continue;
      }

      final result = await permanentDelete(id);
      if (!result.success) {
        failed.add(trash.entityName ?? 'Item #$id');
      }
    }

    if (failed.isEmpty) return const TrashOperationResult(success: true);
    return TrashOperationResult(
      success: false,
      message: 'Some items could not be deleted: ${failed.join(', ')}',
    );
  }

  /// Returns the number of items currently in trash.
  Future<int> getTrashCount() async {
    if (!_sessionManager.hasPermission('view_trash')) {
      return 0;
    }
    final items = await _trashRepository.getAll();
    return items.length;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<List<TrashItem>> _withDeletedByNames(List<TrashItem> items) async {
    final userIds =
        items.map((i) => i.deletedBy).whereType<int>().toSet().toList();
    if (userIds.isEmpty) return items;

    final users = await _userRepository.getAll();
    final names = <int, String>{};
    for (final user in users) {
      if (user.id != null) {
        names[user.id!] = user.fullName;
      }
    }

    return items
        .map(
          (i) => i.copyWith(
            deletedByName: i.deletedBy != null ? names[i.deletedBy] : null,
          ),
        )
        .toList();
  }

  Future<void> _softDeleteEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    switch (entityType) {
      case _entityProduct:
        await _productRepository.softDelete(entityId, txn: txn);
      case _entityCategory:
        await _categoryRepository.softDelete(entityId, txn: txn);
      case _entityUser:
        await _userRepository.softDelete(entityId, txn: txn);
    }
  }

  Future<void> _restoreEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    switch (entityType) {
      case _entityProduct:
        await _productRepository.restore(entityId, txn: txn);
      case _entityCategory:
        await _categoryRepository.restore(entityId, txn: txn);
      case _entityUser:
        await _userRepository.restore(entityId, txn: txn);
    }
  }

  Future<void> _hardDeleteEntity(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    switch (entityType) {
      case _entityProduct:
        await _productRepository.delete(entityId, txn: txn);
      case _entityCategory:
        await _categoryRepository.delete(entityId, txn: txn);
      case _entityUser:
        await _userRepository.permanentlyDelete(entityId, txn: txn);
    }
  }

  Future<TrashOperationResult> _validateRestore(
    String entityType,
    int entityId,
    TrashItem trash,
  ) async {
    switch (entityType) {
      case _entityCategory:
        final snapshot = trash.snapshotMap;
        if (snapshot != null) {
          final name = snapshot['name'] as String?;
          if (name != null && name.isNotEmpty) {
            final existing = await _categoryRepository.getByName(name);
            if (existing != null && existing.id != entityId) {
              return const TrashOperationResult(
                success: false,
                message: 'Another category with this name already exists',
              );
            }
          }
        }
      case _entityUser:
        final snapshot = trash.snapshotMap;
        if (snapshot != null) {
          final username = snapshot['username'] as String?;
          if (username != null && username.isNotEmpty) {
            final existing = await _userRepository.getByUsername(username);
            if (existing != null && existing.id != entityId) {
              return TrashOperationResult(
                success: false,
                message: 'Username "$username" is already in use',
              );
            }
          }
        }
    }
    return const TrashOperationResult(success: true);
  }

  Future<TrashOperationResult> _validatePermanentDelete(
    String entityType,
    int entityId,
    TrashItem trash,
  ) async {
    // Ensure the entity is actually soft-deleted.
    final entity = await _getEntity(entityType, entityId, withDeleted: true);
    if (entity == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Entity not found',
      );
    }

    final DateTime? deletedAt;
    if (entity is Product) {
      deletedAt = entity.deletedAt;
    } else if (entity is Category) {
      deletedAt = entity.deletedAt;
    } else if (entity is User) {
      deletedAt = entity.deletedAt;
    } else {
      deletedAt = null;
    }

    if (deletedAt == null) {
      return const TrashOperationResult(
        success: false,
        message: 'Item must be in trash before permanent deletion',
      );
    }

    switch (entityType) {
      case _entityProduct:
        final product = entity as Product;
        final saleItems =
            await _saleItemRepository.getByProductId(product.id!);
        final stockHistory =
            await _stockHistoryRepository.getByProductId(product.id!);
        if (saleItems.isNotEmpty || stockHistory.isNotEmpty) {
          return const TrashOperationResult(
            success: false,
            message: 'This product has sales or stock history and cannot be '
                'permanently deleted.',
          );
        }
      case _entityUser:
        final user = entity as User;
        final sales =
            await _saleRepository.getByUserId(user.id!, limit: 1);
        final stockHistory =
            await _stockHistoryRepository.getByUserId(user.id!, limit: 1);
        if (sales.isNotEmpty || stockHistory.isNotEmpty) {
          return const TrashOperationResult(
            success: false,
            message: 'This user has sales or stock history and cannot be '
                'permanently deleted.',
          );
        }
    }

    return const TrashOperationResult(success: true);
  }

  Future<dynamic> _getEntity(
    String entityType,
    int entityId, {
    required bool withDeleted,
  }) async {
    switch (entityType) {
      case _entityProduct:
        return _productRepository.getById(entityId);
      case _entityCategory:
        return _categoryRepository.getById(entityId);
      case _entityUser:
        return _userRepository.getByIdWithDeleted(entityId);
    }
    return null;
  }

  Future<void> _clearEntityDependencies(
    String entityType,
    int entityId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await _dbHelper.database;
    if (entityType == _entityCategory) {
      // Remove category references from products so the category can be
      // hard-deleted without violating the foreign key.
      await executor.update(
        'products',
        {'category_id': null},
        where: 'category_id = ?',
        whereArgs: [entityId],
      );
    }
  }

  Future<List<String>> _legacyPathsForEntity(
    String entityType,
    int entityId,
  ) async {
    final paths = <String>[];
    switch (entityType) {
      case _entityProduct:
        final product = await _productRepository.getById(entityId);
        if (product?.imageUrl != null) {
          paths.add(product!.imageUrl!);
        }
      case _entityUser:
        final user = await _userRepository.getByIdWithDeleted(entityId);
        if (user?.profileImagePath != null) {
          paths.add(user!.profileImagePath!);
        }
    }
    return paths;
  }

  Future<(int, int)> _attachmentMetricsForEntity(
    String entityType,
    int entityId,
    String snapshotJson,
  ) async {
    final attachments =
        await _attachmentService.getActiveAttachments(entityType, entityId);
    final attachmentPaths = attachments.map((a) => a.filePath).toSet();

    var totalSizeBytes = 0;
    var count = attachments.length;

    final sizeFutures = attachments
        .map((a) => _fileStorageService.getFileSize(a.filePath))
        .toList();
    final sizes = await Future.wait(sizeFutures);
    for (final size in sizes) {
      totalSizeBytes += size;
    }

    // Also count legacy image paths that are not tracked as attachments.
    Map<String, dynamic>? snapshot;
    try {
      snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
    } catch (_) {
      snapshot = null;
    }

    String? legacyPath;
    if (entityType == _entityProduct) {
      legacyPath = snapshot?['image_url'] as String?;
    } else if (entityType == _entityUser) {
      legacyPath = snapshot?['profile_image_path'] as String?;
    }

    if (legacyPath != null &&
        legacyPath.isNotEmpty &&
        !attachmentPaths.contains(legacyPath)) {
      count += 1;
      totalSizeBytes += await _fileStorageService.getFileSize(legacyPath);
    }

    return (count, totalSizeBytes);
  }

  bool _canDeleteEntity(String entityType) {
    return _sessionManager.hasPermission(_deletePermissionFor(entityType));
  }

  String _deletePermissionFor(String entityType) {
    return switch (entityType) {
      _entityProduct => 'delete_products',
      _entityCategory => 'delete_categories',
      _entityUser => 'delete_users',
      _ => 'restore_trash',
    };
  }

  String _viewPermissionFor(String entityType) {
    return switch (entityType) {
      _entityProduct => 'view_products',
      _entityCategory => 'view_categories',
      _entityUser => 'view_users',
      _ => 'view_trash',
    };
  }

  bool _isForeignKeyViolation(DatabaseException e) {
    final message = e.toString().toLowerCase();
    return message.contains('foreign key') ||
        message.contains('constraint failed');
  }

  /// Builds a JSON snapshot for a product.
  static String snapshotForProduct(Product product) =>
      jsonEncode(product.toMap());

  /// Builds a JSON snapshot for a category.
  static String snapshotForCategory(Category category) =>
      jsonEncode(category.toMap());

  /// Builds a JSON snapshot for a user.  A placeholder password hash is
  /// stored so the snapshot can be parsed with [User.fromMap] for UI
  /// display. The real password hash is never moved or restored from the
  /// trash snapshot.
  static String snapshotForUser(User user) =>
      jsonEncode({
        'id': user.id,
        'username': user.username,
        'password_hash': '',
        'pin': user.pin,
        'pin_length': user.pinLength,
        'role': user.role.name,
        'full_name': user.fullName,
        'color_preference': user.colorPreference,
        'profile_image_path': user.profileImagePath,
        'is_active': user.isActive ? 1 : 0,
        'must_change_password': user.mustChangePassword ? 1 : 0,
        'has_changed_username': user.hasChangedUsername ? 1 : 0,
        'last_login': user.lastLogin?.toIso8601String(),
        'created_at': user.createdAt.toIso8601String(),
        'updated_at': user.updatedAt?.toIso8601String(),
        'deleted_at': user.deletedAt?.toIso8601String(),
      });
}
