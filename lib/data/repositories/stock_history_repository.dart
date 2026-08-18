import 'package:pinoy_pos/data/dao/stock_history_dao.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:sqflite/sqflite.dart';

class StockHistoryRepository {
  final StockHistoryDao _stockHistoryDao = StockHistoryDao();

  Future<int> insert(StockHistory stockHistory, {DatabaseExecutor? txn}) => _stockHistoryDao.insert(stockHistory, txn: txn);
  Future<int> update(StockHistory stockHistory) => _stockHistoryDao.update(stockHistory);
  Future<int> delete(int id) => _stockHistoryDao.delete(id);
  Future<StockHistory?> getById(int id) => _stockHistoryDao.getById(id);
  Future<List<StockHistory>> getAll() => _stockHistoryDao.getAll();
  Future<List<StockHistory>> getByProductId(int productId) => _stockHistoryDao.getByProductId(productId);
  Future<List<StockHistory>> getByUserId(int userId) => _stockHistoryDao.getByUserId(userId);
  Future<List<StockHistory>> getByDateRange(DateTime start, DateTime end) => _stockHistoryDao.getByDateRange(start, end);
}
