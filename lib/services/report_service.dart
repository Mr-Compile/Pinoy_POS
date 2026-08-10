import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class ReportService {
  final SaleRepository _saleRepository = SaleRepository();
  final ProductRepository _productRepository = ProductRepository();
  final AuthService _authService = AuthService();

  Future<double> getTodaySales() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    return _saleRepository.getTotalSalesForDate(now);
  }

  Future<double> getMonthSales() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    return _saleRepository.getTotalSalesForMonth(now.year, now.month);
  }

  Future<int> getLowStockCount() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0;
    }
    final products = await _productRepository.getLowStockProducts();
    return products.length;
  }

  Future<int> getTotalProducts() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0;
    }
    final products = await _productRepository.getActiveProducts();
    return products.length;
  }

  Future<int> getTotalUsers() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0;
    }
    // This would need a user repository method
    return 0;
  }
}
