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
  Future<List<Sale>> getAllActive() => _saleDao.getAllActive();
  Future<List<Sale>> getDeleted() => _saleDao.getDeleted();
  Future<List<Sale>> getByUserId(int userId) => _saleDao.getByUserId(userId);
  Future<List<Sale>> getByDateRange(DateTime start, DateTime end) => _saleDao.getByDateRange(start, end);
  Future<List<Sale>> getByDateRangeAndUser(DateTime start, DateTime end, int userId) => _saleDao.getByDateRangeAndUser(start, end, userId);
  Future<double> getTotalSalesForDate(DateTime date) => _saleDao.getTotalSalesForDate(date);
  Future<double> getTotalSalesForMonth(int year, int month) => _saleDao.getTotalSalesForMonth(year, month);
  Future<double> getTotalSalesForUser(int userId) => _saleDao.getTotalSalesForUser(userId);
  Future<double> getTotalSalesForDateForUser(DateTime date, int userId) => _saleDao.getTotalSalesForDateForUser(date, userId);
  Future<double> getTotalSalesForMonthForUser(int year, int month, int userId) => _saleDao.getTotalSalesForMonthForUser(year, month, userId);
}
