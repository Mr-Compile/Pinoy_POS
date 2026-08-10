import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/services/stock_service.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class SalesService {
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final StockService _stockService = StockService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<Sale>> getSales() async {
    if (!_authService.hasPermission('view_sales')) {
      return [];
    }

    if (_authService.currentUser?.role == UserRole.staff) {
      return _saleRepository.getByUserId(_authService.currentUser!.id!);
    }

    return _saleRepository.getAllActive();
  }

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async {
    if (!_authService.hasPermission('view_sales')) {
      return [];
    }

    if (_authService.currentUser?.role == UserRole.staff) {
      return _saleRepository.getByDateRangeAndUser(
        start,
        end,
        _authService.currentUser!.id!,
      );
    }

    return _saleRepository.getByDateRange(start, end);
  }

  Future<Sale?> getSaleById(int id) async {
    if (!_authService.hasPermission('view_sales')) {
      return null;
    }

    final sale = await _saleRepository.getById(id);
    
    if (sale == null) return null;

    if (_authService.currentUser?.role == UserRole.staff &&
        sale.userId != _authService.currentUser!.id) {
      return null;
    }

    return sale;
  }

  Future<List<SaleItem>> getSaleItems(int saleId) async {
    if (!_authService.hasPermission('view_sales')) {
      return [];
    }

    return _saleItemRepository.getBySaleId(saleId);
  }

  Future<bool> createSale({
    required List<SaleItem> items,
    required double totalAmount,
    required double cashReceived,
    String? notes,
  }) async {
    if (!_authService.hasPermission('create_sale')) {
      return false;
    }

    if (items.isEmpty) {
      return false;
    }

    if (cashReceived < totalAmount) {
      return false;
    }

    return await _dbHelper.transaction((txn) async {
      final change = cashReceived - totalAmount;
      final receiptNumber = SecurityHelper.generateReceiptNumber();

      final sale = Sale(
        totalAmount: totalAmount,
        cashReceived: cashReceived,
        change: change,
        userId: _authService.currentUser!.id!,
        createdAt: DateTime.now(),
        receiptNumber: receiptNumber,
        notes: notes,
      );

      final saleId = await _saleRepository.insert(sale);

      for (var item in items) {
        final saleItem = item.copyWith(saleId: saleId);
        await _saleItemRepository.insert(saleItem);

        final stockDeducted = await _stockService.deductStockForSale(
          item.productId,
          item.quantity,
        );

        if (!stockDeducted) {
          throw Exception('Insufficient stock');
        }
      }

      return true;
    });
  }

  Future<bool> voidSale(int saleId) async {
    if (!_authService.hasPermission('void_sale')) {
      return false;
    }

    return await _dbHelper.transaction((txn) async {
      final sale = await _saleRepository.getById(saleId);
      if (sale == null) return false;

      final items = await _saleItemRepository.getBySaleId(saleId);

      for (var item in items) {
        await _stockService.addStock(
          item.productId,
          item.quantity,
          'Void sale: ${sale.receiptNumber}',
        );
      }

      await _saleRepository.softDelete(saleId);
      return true;
    });
  }

  Future<double> getTodaySales() async {
    if (!_authService.hasPermission('view_sales')) {
      return 0.0;
    }

    final now = DateTime.now();
    return _saleRepository.getTotalSalesForDate(now);
  }

  Future<double> getMonthSales() async {
    if (!_authService.hasPermission('view_sales')) {
      return 0.0;
    }

    final now = DateTime.now();
    return _saleRepository.getTotalSalesForMonth(now.year, now.month);
  }

  Future<double> getUserSales(int userId) async {
    if (!_authService.hasPermission('view_sales')) {
      return 0.0;
    }

    return _saleRepository.getTotalSalesForUser(userId);
  }
}
