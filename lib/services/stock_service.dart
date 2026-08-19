import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/stock_history_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:sqflite/sqflite.dart';

class StockService {
  final ProductRepository _productRepository = ProductRepository();
  final StockHistoryRepository _stockHistoryRepository = StockHistoryRepository();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final NotificationService _notificationService = NotificationService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<StockHistory>> getStockHistory(int productId) async {
    if (!_sessionManager.hasPermission('view_stock')) {
      return [];
    }
    return _stockHistoryRepository.getByProductId(productId);
  }

  /// Add stock to a product. Increases stock_quantity, inserts stock_history,
  /// logs activity, and generates a low-stock notification if needed.
  ///
  /// Staff are allowed to add stock (increase only). Manual decrease /
  /// arbitrary adjustment is rejected by [adjustStock] for Staff because
  /// they lack the `adjust_stock` permission.
  Future<bool> addStock(int productId, int quantity, String? reason) async {
    if (!_sessionManager.hasPermission('add_stock')) {
      await _activityLogService.logActivity(
        action: 'unauthorized_add_stock',
        entity: 'product',
        entityId: productId,
        details: 'Attempted to add stock without permission',
      );
      throw AuthorizationException('add_stock');
    }

    if (quantity <= 0) {
      return false;
    }

    return await _dbHelper.transaction((txn) async {
      final product = await _productRepository.getById(productId, txn: txn);
      if (product == null) return false;
      if (!product.isActive) return false;

      final previousStock = product.stock;
      final newStock = previousStock + quantity;

      await _productRepository.updateStock(productId, newStock, txn: txn);

      final history = StockHistory(
        productId: productId,
        operation: StockOperationType.add,
        quantity: quantity,
        previousStock: previousStock,
        newStock: newStock,
        reason: reason,
        userId: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history, txn: txn);

      // Log activity
      await _activityLogService.logActivity(
        action: 'add_stock',
        entity: 'product',
        entityId: productId,
        details: 'Added $quantity units. Stock: $previousStock → $newStock',
        txn: txn,
      );

      return true;
    });
  }

  /// Adjust stock to a new absolute value. Validates quantity, calculates
  /// previous and new stock, updates atomically, inserts history, and logs.
  ///
  /// Staff do NOT have the `adjust_stock` permission, so this method will
  /// always throw [AuthorizationException] for Staff. This enforces the
  /// "add stock only" restriction at the service layer, not just in the UI.
  Future<bool> adjustStock(int productId, int newStock, String reason) async {
    if (!_sessionManager.hasPermission('adjust_stock')) {
      await _activityLogService.logActivity(
        action: 'unauthorized_adjust_stock',
        entity: 'product',
        entityId: productId,
        details: 'Attempted to adjust stock without permission',
      );
      throw AuthorizationException('adjust_stock');
    }

    if (newStock < 0) {
      return false;
    }

    if (reason.isEmpty) {
      return false;
    }

    return await _dbHelper.transaction((txn) async {
      final product = await _productRepository.getById(productId, txn: txn);
      if (product == null) return false;

      final previousStock = product.stock;
      final quantity = newStock - previousStock;

      await _productRepository.updateStock(productId, newStock, txn: txn);

      final history = StockHistory(
        productId: productId,
        operation: StockOperationType.adjust,
        quantity: quantity,
        previousStock: previousStock,
        newStock: newStock,
        reason: reason,
        userId: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history, txn: txn);

      // Log activity
      await _activityLogService.logActivity(
        action: 'adjust_stock',
        entity: 'product',
        entityId: productId,
        details: 'Adjusted stock from $previousStock to $newStock. Reason: $reason',
        txn: txn,
      );

      // Generate low-stock notification if product is now low.
      // Dedup: only create a notification if there isn't already an
      // unread one with the same title/message for the current user.
      // This prevents spam when multiple adjustments keep the product
      // below the threshold. Once the user reads the notification, a
      // new low-stock event will generate a fresh alert.
      if (product.minStock > 0 && newStock <= product.minStock) {
        final userId = _sessionManager.currentUser?.id;
        if (userId != null) {
          final title = 'Low Stock Alert';
          final message =
              '${product.name} is at $newStock units (min: ${product.minStock})';
          final alreadyNotified = await _notificationService.hasUnreadNotification(
            userId: userId,
            type: 'low_stock',
            title: title,
            message: message,
            txn: txn,
          );
          if (!alreadyNotified) {
            await _notificationService.createNotification(
              title: title,
              message: message,
              type: 'low_stock',
              txn: txn,
            );
          }
        }
      }

      return true;
    });
  }

  /// Deduct stock for a sale. Called within a transaction by SalesService.
  ///
  /// Accepts an optional [txn] so it can participate in the caller's
  /// transaction. When [txn] is provided, no new transaction is opened
  /// (avoiding nested transactions which sqflite does not support). When
  /// [txn] is null, a new transaction is created.
  ///
  /// Validates stock availability, deducts, and inserts history.
  Future<bool> deductStockForSale(int productId, int quantity, {DatabaseExecutor? txn}) async {
    Future<bool> doDeduct(DatabaseExecutor executor) async {
      final product = await _productRepository.getById(productId, txn: executor);
      if (product == null) return false;

      if (product.stock < quantity) {
        return false;
      }

      final previousStock = product.stock;
      final newStock = previousStock - quantity;

      await _productRepository.updateStock(productId, newStock, txn: executor);

      final history = StockHistory(
        productId: productId,
        operation: StockOperationType.sale,
        quantity: quantity,
        previousStock: previousStock,
        newStock: newStock,
        userId: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history, txn: executor);

      // Generate low-stock notification if product is now low.
      // Dedup: only create a notification if there isn't already an
      // unread one with the same title/message for the current user.
      if (product.minStock > 0 && newStock <= product.minStock) {
        final userId = _sessionManager.currentUser?.id;
        if (userId != null) {
          final title = 'Low Stock Alert';
          final message =
              '${product.name} is at $newStock units (min: ${product.minStock})';
          final alreadyNotified = await _notificationService.hasUnreadNotification(
            userId: userId,
            type: 'low_stock',
            title: title,
            message: message,
            txn: executor,
          );
          if (!alreadyNotified) {
            await _notificationService.createNotification(
              title: title,
              message: message,
              type: 'low_stock',
              txn: executor,
            );
          }
        }
      }

      return true;
    }

    if (txn != null) {
      return doDeduct(txn);
    }
    return await _dbHelper.transaction((t) => doDeduct(t));
  }
}
