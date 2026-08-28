import 'package:pinoy_pos/data/dao/sale_dao.dart';
import 'package:pinoy_pos/data/models/sale.dart';
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
    int limit = 500,
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
}
