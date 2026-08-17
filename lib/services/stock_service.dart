import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/stock_history_repository.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';

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
      final product = await _productRepository.getById(productId);
      if (product == null) return false;

      final previousStock = product.stock;
      final newStock = previousStock + quantity;

      await _productRepository.updateStock(productId, newStock);

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

      await _stockHistoryRepository.insert(history);

      // Log activity
      await _activityLogService.logActivity(
        action: 'add_stock',
        entity: 'product',
        entityId: productId,
        details: 'Added $quantity units. Stock: $previousStock → $newStock',
      );

      return true;
    });
  }

  /// Adjust stock to a new absolute value. Validates quantity, calculates
  /// previous and new stock, updates atomically, inserts history, and logs.
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
      final product = await _productRepository.getById(productId);
      if (product == null) return false;

      final previousStock = product.stock;
      final quantity = newStock - previousStock;

      await _productRepository.updateStock(productId, newStock);

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

      await _stockHistoryRepository.insert(history);

      // Log activity
      await _activityLogService.logActivity(
        action: 'adjust_stock',
        entity: 'product',
        entityId: productId,
        details: 'Adjusted stock from $previousStock to $newStock. Reason: $reason',
      );

      // Generate low-stock notification if product is now low
      if (product.minStock > 0 && newStock <= product.minStock) {
        await _notificationService.createNotification(
          title: 'Low Stock Alert',
          message: '${product.name} is at $newStock units (min: ${product.minStock})',
          type: 'low_stock',
        );
      }

      return true;
    });
  }

  /// Deduct stock for a sale. Called within a transaction by SalesService.
  /// Validates stock availability, deducts atomically, and inserts history.
  Future<bool> deductStockForSale(int productId, int quantity) async {
    return await _dbHelper.transaction((txn) async {
      final product = await _productRepository.getById(productId);
      if (product == null) return false;

      if (product.stock < quantity) {
        return false;
      }

      final previousStock = product.stock;
      final newStock = previousStock - quantity;

      await _productRepository.updateStock(productId, newStock);

      final history = StockHistory(
        productId: productId,
        operation: StockOperationType.sale,
        quantity: quantity,
        previousStock: previousStock,
        newStock: newStock,
        userId: _sessionManager.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history);

      // Generate low-stock notification if product is now low
      if (product.minStock > 0 && newStock <= product.minStock) {
        await _notificationService.createNotification(
          title: 'Low Stock Alert',
          message: '${product.name} is at $newStock units (min: ${product.minStock})',
          type: 'low_stock',
        );
      }

      return true;
    });
  }
}
