import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/data/dao/base_dao.dart';
import 'package:pinoy_pos/data/models/calendar_day_sales.dart';
import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/user.dart';
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
      where:
          'created_at BETWEEN ? AND ? AND deleted_at IS NULL '
          "AND payment_status = 'confirmed'",
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
      where:
          'created_at BETWEEN ? AND ? AND user_id = ? AND deleted_at IS NULL '
          "AND payment_status = 'confirmed'",
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
      conditions.add('created_at >= ? AND created_at < ?');
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

  /// Staff sales performance over a date range, optionally filtered by role.
  ///
  /// Only confirmed, non-deleted sales are counted. Results are ordered by
  /// total sales descending.
  Future<List<StaffSalesSummary>> getStaffSalesSummary(
    DateTime start,
    DateTime end, {
    UserRole? role,
  }) async {
    final database = await db;
    final conditions = <String>[
      "s.created_at >= ? AND s.created_at < ?",
      "s.deleted_at IS NULL",
      "s.payment_status = 'confirmed'",
    ];
    final args = <Object?>[start.toIso8601String(), end.toIso8601String()];

    if (role != null) {
      conditions.add('u.role = ?');
      args.add(role.name);
    }

    final result = await database.rawQuery('''
      SELECT s.user_id, u.full_name, u.role,
             COALESCE(SUM(s.total_amount), 0) as total_sales,
             COUNT(*) as transaction_count
      FROM sales s
      INNER JOIN users u ON s.user_id = u.id
      WHERE ${conditions.join(' AND ')}
      GROUP BY s.user_id
      ORDER BY total_sales DESC
    ''', args);

    return result.map(StaffSalesSummary.fromMap).toList();
  }

  // â”€â”€ Centralised sales-analytics queries â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns summary numbers for confirmed, non-deleted sales in a range.
  ///
  /// Result map keys: `total_sales`, `transaction_count`.
  Future<Map<String, dynamic>> getSalesSummary(
    DateTime start,
    DateTime end, {
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    final result = await executor.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) as total_sales,
             COUNT(*) as transaction_count
      FROM sales
      WHERE ${conditions.where}
    ''', conditions.args);

    return result.first;
  }

  /// Returns the total quantity of items sold for confirmed sales in a range.
  Future<int> getItemsSold(
    DateTime start,
    DateTime end, {
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    final result = await executor.rawQuery('''
      SELECT COALESCE(SUM(si.quantity), 0) as items_sold
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      WHERE ${conditions.where}
    ''', conditions.args);

    return (result.first['items_sold'] as num?)?.toInt() ?? 0;
  }

  /// Returns a sales trend grouped by [groupBy] for the given range.
  ///
  /// For [ReportGroupBy.week] the SQL first groups by day and the caller is
  /// expected to collapse days to week starts in Dart.
  Future<List<DailySalesPoint>> getSalesTrend(
    DateTime start,
    DateTime end, {
    required ReportGroupBy groupBy,
    int? userId,
  }) async {
    final database = await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    late String select;
    late String groupBySql;
    late String pattern;

    switch (groupBy) {
      case ReportGroupBy.hour:
        select = "substr(created_at, 1, 13) as bucket";
        groupBySql = 'bucket';
        pattern = "yyyy-MM-ddTHH";
      case ReportGroupBy.day:
        select = "substr(created_at, 1, 10) as bucket";
        groupBySql = 'bucket';
        pattern = "yyyy-MM-dd";
      case ReportGroupBy.week:
        // Group by day first; week collapsing is done by the caller.
        select = "substr(created_at, 1, 10) as bucket";
        groupBySql = 'bucket';
        pattern = "yyyy-MM-dd";
      case ReportGroupBy.month:
        select = "substr(created_at, 1, 7) as bucket";
        groupBySql = 'bucket';
        pattern = "yyyy-MM";
    }

    final result = await database.rawQuery('''
      SELECT $select,
             COALESCE(SUM(total_amount), 0) as total,
             COUNT(*) as count
      FROM sales
      WHERE ${conditions.where}
      GROUP BY $groupBySql
      ORDER BY bucket
    ''', conditions.args);

    return result.map((row) {
      final bucket = row['bucket'] as String;
      final parsed = _parseBucket(bucket, pattern);
      return DailySalesPoint(
        date: parsed,
        total: (row['total'] as num?)?.toDouble() ?? 0.0,
        count: (row['count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// Returns payment-method totals for confirmed sales in a range.
  Future<List<PaymentBreakdown>> getPaymentBreakdown(
    DateTime start,
    DateTime end, {
    int? userId,
  }) async {
    final database = await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    final result = await database.rawQuery('''
      SELECT payment_method,
             COALESCE(SUM(total_amount), 0) as total,
             COUNT(*) as count
      FROM sales
      WHERE ${conditions.where}
      GROUP BY payment_method
      ORDER BY total DESC
    ''', conditions.args);

    return result.map(PaymentBreakdown.fromMap).toList();
  }

  /// Returns total confirmed sales grouped by product category.
  ///
  /// Products with no category are reported under 'Uncategorized'.
  Future<List<CategorySalesResult>> getCategorySales(
    DateTime start,
    DateTime end, {
    int? userId,
  }) async {
    final database = await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    final result = await database.rawQuery('''
      SELECT c.id AS category_id,
             COALESCE(c.name, 'Uncategorized') AS category_name,
             COALESCE(SUM(s.total_amount), 0) AS total_sales,
             COUNT(DISTINCT s.id) AS transaction_count,
             COALESCE(SUM(si.quantity), 0) AS items_sold
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN products p ON p.id = si.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE ${conditions.where}
      GROUP BY COALESCE(c.name, 'Uncategorized')
      ORDER BY total_sales DESC
    ''', conditions.args);

    return result.map(CategorySalesResult.fromMap).toList();
  }

  /// Returns per-day totals for confirmed sales in a range, suitable for
  /// populating a calendar view.
  Future<List<CalendarDaySales>> getCalendarDaySales(
    DateTime start,
    DateTime end, {
    int? userId,
  }) async {
    final database = await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    final result = await database.rawQuery('''
      SELECT substr(created_at, 1, 10) as date,
             COALESCE(SUM(total_amount), 0) as total_sales,
             COUNT(*) as transaction_count
      FROM sales
      WHERE ${conditions.where}
      GROUP BY date
      ORDER BY date
    ''', conditions.args);

    return result.map(CalendarDaySales.fromMap).toList();
  }

  /// Confirmed sales in a range, newest first.
  Future<List<Sale>> getConfirmedSalesForRange(
    DateTime start,
    DateTime end, {
    int? userId,
    String? paymentMethod,
    String? search,
    int limit = 500,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await db;
    final conditions = _confirmedRangeConditions(start, end, userId);

    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      conditions.add('payment_method = ?', paymentMethod);
    }

    if (search != null && search.trim().isNotEmpty) {
      conditions.add(
        '(receipt_number LIKE ? OR reference_number LIKE ? OR customer_name LIKE ?)',
      );
      final like = '%${search.trim()}%';
      conditions.args.add(like);
      conditions.args.add(like);
      conditions.args.add(like);
    }

    final maps = await executor.query(
      tableName,
      where: conditions.where,
      whereArgs: conditions.args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  _WhereClause _confirmedRangeConditions(
    DateTime start,
    DateTime end,
    int? userId,
  ) {
    final conditions = <String>[
      'created_at >= ?',
      'created_at < ?',
      "deleted_at IS NULL",
      "payment_status = 'confirmed'",
    ];
    final args = <Object?>[start.toIso8601String(), end.toIso8601String()];

    if (userId != null) {
      conditions.add('user_id = ?');
      args.add(userId);
    }

    return _WhereClause(conditions.join(' AND '), args);
  }

  DateTime _parseBucket(String bucket, String pattern) {
    switch (pattern) {
      case 'yyyy-MM-ddTHH':
        return DateTime.parse('$bucket:00:00.000');
      case 'yyyy-MM-dd':
        return DateTime.parse('${bucket}T00:00:00.000');
      case 'yyyy-MM':
        return DateTime.parse('$bucket-01T00:00:00.000');
    }
    return DateTime.parse(bucket);
  }
}

/// Simple WHERE clause builder for the DAO's raw queries.
class _WhereClause {
  String where;
  final List<Object?> args;

  _WhereClause(this.where, this.args);

  void add(String condition, [Object? value]) {
    where = '$where AND $condition';
    if (value != null) args.add(value);
  }
}
