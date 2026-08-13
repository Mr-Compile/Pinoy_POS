import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';

class ReportService {
  final SaleRepository _saleRepository = SaleRepository();
  final ProductRepository _productRepository = ProductRepository();
  final UserRepository _userRepository = UserRepository();
  final AuthService _authService = AuthService();

  // --- Business metrics (Owner / Staff) ---

  Future<double> getTodaySales() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    // Staff: only own sales
    if (_authService.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForDateForUser(
        now,
        _authService.currentUser!.id!,
      );
    }
    return _saleRepository.getTotalSalesForDate(now);
  }

  Future<double> getMonthSales() async {
    if (!_authService.hasPermission('view_reports')) {
      return 0.0;
    }
    final now = DateTime.now();
    if (_authService.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForMonthForUser(
        now.year,
        now.month,
        _authService.currentUser!.id!,
      );
    }
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

  // --- System metrics (System Admin) ---

  Future<int> getTotalUsers() async {
    if (!_authService.hasPermission('manage_users')) {
      return 0;
    }
    final users = await _userRepository.getAllActive();
    return users.length;
  }

  Future<int> getActiveUsers() async {
    if (!_authService.hasPermission('manage_users')) {
      return 0;
    }
    final users = await _userRepository.getActiveUsers();
    return users.length;
  }

  /// Returns the path to the most recent backup file, or null if none exists.
  Future<String?> getLastBackupPath() async {
    if (!_authService.hasPermission('backup_restore')) {
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = Directory(dir.path)
          .listSync()
          .where((f) => f.path.endsWith('.db') && f.path.contains('backup'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) return null;
      return files.first.path;
    } catch (_) {
      return null;
    }
  }

  /// Returns the last backup date, or null if no backup exists.
  Future<DateTime?> getLastBackupDate() async {
    final path = await getLastBackupPath();
    if (path == null) return null;
    try {
      final stat = await File(path).stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  }
}
