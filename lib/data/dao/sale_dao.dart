import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:sqflite/sqflite.dart';

class SaleDao extends BaseDao<Sale> {
  @override
  String get tableName => 'sales';

  @override
  Sale fromMap(Map<String, dynamic> map) => Sale.fromMap(map);

  Future<List<Sale>> getByUserId(int userId, {int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Sale>> getByDateRange(DateTime start, DateTime end, {int limit = 500}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'created_at BETWEEN ? AND ? AND deleted_at IS NULL',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<List<Sale>> getByDateRangeAndUser(
    DateTime start,
    DateTime end,
    int userId, {
    int limit = 200,
  }) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: 'created_at BETWEEN ? AND ? AND user_id = ? AND deleted_at IS NULL',
      whereArgs: [start.toIso8601String(), end.toIso8601String(), userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  Future<double> getTotalSalesForDate(DateTime date) async {
    final database = await db;
    final start = startOfDay(date);
    final end = start.add(const Duration(days: 1));

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND deleted_at IS NULL
        AND payment_status = 'confirmed'
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForMonth(int year, int month) async {
    final database = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND deleted_at IS NULL
        AND payment_status = 'confirmed'
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForUser(int userId) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE user_id = ? AND deleted_at IS NULL
        AND payment_status = 'confirmed'
    ''', [userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForDateForUser(DateTime date, int userId) async {
    final database = await db;
    final start = startOfDay(date);
    final end = start.add(const Duration(days: 1));

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND user_id = ? AND deleted_at IS NULL
        AND payment_status = 'confirmed'
    ''', [start.toIso8601String(), end.toIso8601String(), userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesForMonthForUser(int year, int month, int userId) async {
    final database = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final result = await database.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total
      FROM sales
      WHERE created_at >= ? AND created_at < ? AND user_id = ? AND deleted_at IS NULL
        AND payment_status = 'confirmed'
    ''', [start.toIso8601String(), end.toIso8601String(), userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns a sale with the same reference number and payment method that is
  /// still active (not deleted, not cancelled, not refunded). Used to prevent
  /// accidental duplicate GCash references.
  Future<Sale?> findByReferenceNumber(
    String referenceNumber,
    String paymentMethod, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where:
          'reference_number = ? AND payment_method = ? AND deleted_at IS NULL '
          "AND payment_status NOT IN ('cancelled', 'refunded')",
      whereArgs: [referenceNumber, paymentMethod],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Returns all non-deleted, non-cancelled sales with the given [paymentStatus].
  Future<List<Sale>> getByPaymentStatus(
    String paymentStatus, {
    int limit = 200,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final maps = await executor.query(
      tableName,
      where:
          'payment_status = ? AND deleted_at IS NULL '
          "AND payment_status NOT IN ('cancelled', 'refunded')",
      whereArgs: [paymentStatus],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Returns pending GCash payments awaiting owner/admin verification.
  Future<List<Sale>> getPendingPayments({int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      tableName,
      where: "payment_status = 'pending' AND deleted_at IS NULL",
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Returns sales filtered by optional date range, payment method, payment
  /// status, search query, and user. All filters avoid loading the full
  /// historical table into memory.
  Future<List<Sale>> getFilteredSales({
    DateTime? start,
    DateTime? end,
    String? paymentMethod,
    String? paymentStatus,
    String? search,
    int? userId,
    int limit = 500,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];

    if (start != null && end != null) {
      conditions.add('created_at BETWEEN ? AND ?');
      args.add(start.toIso8601String());
      args.add(end.toIso8601String());
    }

    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      conditions.add('payment_method = ?');
      args.add(paymentMethod);
    }

    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      conditions.add('payment_status = ?');
      args.add(paymentStatus);
    } else {
      // By default, hide cancelled/refunded sales from the sales list.
      conditions.add("payment_status NOT IN ('cancelled', 'refunded')");
    }

    if (userId != null) {
      conditions.add('user_id = ?');
      args.add(userId);
    }

    if (search != null && search.trim().isNotEmpty) {
      conditions.add(
        '(receipt_number LIKE ? OR reference_number LIKE ? OR customer_name LIKE ?)',
      );
      final like = '%${search.trim()}%';
      args.add(like);
      args.add(like);
      args.add(like);
    }

    final maps = await executor.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }
}
