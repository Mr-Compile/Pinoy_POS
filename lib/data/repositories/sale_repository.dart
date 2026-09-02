import 'package:pinoy_pos/data/dao/sale_dao.dart';
import 'package:pinoy_pos/data/models/calendar_day_sales.dart';
import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sales_by_hour_point.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:sqflite/sqflite.dart';

class SaleRepository {
  final SaleDao _saleDao = SaleDao();

  Future<int> insert(Sale sale, {DatabaseExecutor? txn}) => _saleDao.insert(sale, txn: txn);
  Future<int> update(Sale sale, {DatabaseExecutor? txn}) => _saleDao.update(sale, txn: txn);
  Future<int> delete(int id, {DatabaseExecutor? txn}) => _saleDao.delete(id, txn: txn);
  Future<int> softDelete(int id, {DatabaseExecutor? txn}) => _saleDao.softDelete(id, txn: txn);
  Future<int> restore(int id, {DatabaseExecutor? txn}) => _saleDao.restore(id, txn: txn);
  Future<Sale?> getById(int id, {DatabaseExecutor? txn}) => _saleDao.getById(id, txn: txn);
  Future<List<Sale>> getAll() => _saleDao.getAll();
  Future<List<Sale>> getAllActive({int? limit}) => _saleDao.getAllActive(limit: limit);
  Future<List<Sale>> getDeleted() => _saleDao.getDeleted();
  Future<List<Sale>> getByUserId(int userId, {int limit = 200}) => _saleDao.getByUserId(userId, limit: limit);
  Future<List<Sale>> getByDateRange(DateTime start, DateTime end, {int limit = 500}) => _saleDao.getByDateRange(start, end, limit: limit);
  Future<List<Sale>> getByDateRangeAndUser(DateTime start, DateTime end, int userId, {int limit = 200}) => _saleDao.getByDateRangeAndUser(start, end, userId, limit: limit);
  Future<double> getTotalSalesForDate(DateTime date) => _saleDao.getTotalSalesForDate(date);
  Future<double> getTotalSalesForMonth(int year, int month) => _saleDao.getTotalSalesForMonth(year, month);
  Future<double> getTotalSalesForUser(int userId) => _saleDao.getTotalSalesForUser(userId);
  Future<double> getTotalSalesForDateForUser(DateTime date, int userId) => _saleDao.getTotalSalesForDateForUser(date, userId);
  Future<double> getTotalSalesForMonthForUser(int year, int month, int userId) => _saleDao.getTotalSalesForMonthForUser(year, month, userId);

  Future<Sale?> findByReferenceNumber(
    String referenceNumber,
    String paymentMethod, {
    DatabaseExecutor? txn,
  }) =>
      _saleDao.findByReferenceNumber(referenceNumber, paymentMethod, txn: txn);

  Future<List<Sale>> getByPaymentStatus(
    String paymentStatus, {
    int limit = 200,
    DatabaseExecutor? txn,
  }) =>
      _saleDao.getByPaymentStatus(paymentStatus, limit: limit, txn: txn);

  Future<List<Sale>> getPendingPayments({int limit = 200}) => _saleDao.getPendingPayments(limit: limit);

  Future<List<Sale>> getFilteredSales({
    DateTime? start,
    DateTime? end,
    String? paymentMethod,
    String? paymentStatus,
    String? search,
    int? userId,
    int? limit = 500,
    DatabaseExecutor? txn,
  }) =>
      _saleDao.getFilteredSales(
        start: start,
        end: end,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        search: search,
        userId: userId,
        limit: limit,
        txn: txn,
      );

  Future<List<StaffSalesSummary>> getStaffSalesSummary(
    DateTime start,
    DateTime end, {
    UserRole? role,
  }) =>
      _saleDao.getStaffSalesSummary(start, end, role: role);

  // ── Centralised sales-analytics repository methods ───────────────────

  Future<Map<String, dynamic>> getSalesSummary(
    DateTime start,
    DateTime end, {
    int? userId,
    DatabaseExecutor? txn,
  }) =>
      _saleDao.getSalesSummary(start, end, userId: userId, txn: txn);

  Future<int> getItemsSold(
    DateTime start,
    DateTime end, {
    int? userId,
    DatabaseExecutor? txn,
  }) =>
      _saleDao.getItemsSold(start, end, userId: userId, txn: txn);

  Future<List<DailySalesPoint>> getSalesTrend(
    DateTime start,
    DateTime end, {
    required ReportGroupBy groupBy,
    int? userId,
  }) =>
      _saleDao.getSalesTrend(start, end, groupBy: groupBy, userId: userId);

  Future<List<PaymentBreakdown>> getPaymentBreakdown(
    DateTime start,
    DateTime end, {
    int? userId,
  }) =>
      _saleDao.getPaymentBreakdown(start, end, userId: userId);

  Future<List<CategorySalesResult>> getCategorySales(
    DateTime start,
    DateTime end, {
    int? userId,
  }) =>
      _saleDao.getCategorySales(start, end, userId: userId);

  Future<List<SalesByHourPoint>> getSalesByHourOfDay(
    DateTime start,
    DateTime end, {
    int? userId,
  }) =>
      _saleDao.getSalesByHourOfDay(start, end, userId: userId);

  Future<List<CalendarDaySales>> getCalendarDaySales(
    DateTime start,
    DateTime end, {
    int? userId,
  }) =>
      _saleDao.getCalendarDaySales(start, end, userId: userId);

  Future<List<Sale>> getConfirmedSalesForRange(
    DateTime start,
    DateTime end, {
    int? userId,
    String? paymentMethod,
    String? search,
    int? limit = 500,
    DatabaseExecutor? txn,
  }) =>
      _saleDao.getConfirmedSalesForRange(
        start,
        end,
        userId: userId,
        paymentMethod: paymentMethod,
        search: search,
        limit: limit,
        txn: txn,
      );
}
