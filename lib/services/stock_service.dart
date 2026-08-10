import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/stock_history_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class StockService {
  final ProductRepository _productRepository = ProductRepository();
  final StockHistoryRepository _stockHistoryRepository = StockHistoryRepository();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<StockHistory>> getStockHistory(int productId) async {
    if (!_authService.hasPermission('view_stock')) {
      return [];
    }
    return _stockHistoryRepository.getByProductId(productId);
  }

  Future<bool> addStock(int productId, int quantity, String? reason) async {
    if (!_authService.hasPermission('add_stock')) {
      return false;
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
        userId: _authService.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history);
      return true;
    });
  }

  Future<bool> adjustStock(int productId, int newStock, String reason) async {
    if (!_authService.hasPermission('adjust_stock')) {
      return false;
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
        userId: _authService.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history);
      return true;
    });
  }

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
        userId: _authService.currentUser?.id,
        createdAt: DateTime.now(),
      );

      await _stockHistoryRepository.insert(history);
      return true;
    });
  }
}
