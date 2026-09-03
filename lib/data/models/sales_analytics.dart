import 'package:pinoy_pos/data/models/category_sales_result.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/payment_breakdown.dart';
import 'package:pinoy_pos/data/models/peak_sales_period.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/staff_sales_summary.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';

/// Comparison between the current period and the previous equivalent period.
class SalesPeriodComparison {
  final double previousTotalSales;
  final int previousTransactionCount;
  final double previousAverageTransaction;
  final int previousItemsSold;

  const SalesPeriodComparison({
    required this.previousTotalSales,
    required this.previousTransactionCount,
    required this.previousAverageTransaction,
    required this.previousItemsSold,
  });

  double? _pct(double current, double previous) {
    if (previous == 0) {
      if (current == 0) return null;
      return 100.0;
    }
    return ((current - previous) / previous) * 100;
  }

  double? totalChangePercent(double currentTotal) => _pct(currentTotal, previousTotalSales);

  double? transactionCountChangePercent(int currentCount) =>
      _pct(currentCount.toDouble(), previousTransactionCount.toDouble());

  double? averageTransactionChangePercent(double currentAverage) =>
      _pct(currentAverage, previousAverageTransaction);

  double? itemsSoldChangePercent(int currentItems) =>
      _pct(currentItems.toDouble(), previousItemsSold.toDouble());

  factory SalesPeriodComparison.empty() => const SalesPeriodComparison(
        previousTotalSales: 0.0,
        previousTransactionCount: 0,
        previousAverageTransaction: 0.0,
        previousItemsSold: 0,
      );
}

/// Complete analytics for a selected reporting period.
class SalesAnalytics {
  final ReportingPeriodBounds bounds;
  final double totalSales;
  final int transactionCount;
  final double averageTransaction;
  final int itemsSold;
  final SalesPeriodComparison comparison;
  final List<DailySalesPoint> trend;
  final List<DailySalesPoint> previousTrend;
  final List<PaymentBreakdown> paymentBreakdown;
  final List<TopProductResult> topProducts;
  final List<CategorySalesResult> categorySales;
  final List<StaffSalesSummary> staffSummaries;
  final PeakSalesPeriod peakSalesPeriod;
  final List<Sale> sales;
  final String? paymentMethod;
  final String? paymentStatus;
  final int? staffUserId;

  const SalesAnalytics({
    required this.bounds,
    required this.totalSales,
    required this.transactionCount,
    required this.averageTransaction,
    required this.itemsSold,
    required this.comparison,
    required this.trend,
    required this.previousTrend,
    required this.paymentBreakdown,
    required this.topProducts,
    required this.categorySales,
    required this.staffSummaries,
    this.peakSalesPeriod = const PeakSalesPeriod(),
    required this.sales,
    this.paymentMethod,
    this.paymentStatus,
    this.staffUserId,
  });

  /// Empty state used for permission-denied or zero-sales periods.
  factory SalesAnalytics.empty(ReportingPeriodBounds bounds) => SalesAnalytics(
        bounds: bounds,
        totalSales: 0.0,
        transactionCount: 0,
        averageTransaction: 0.0,
        itemsSold: 0,
        comparison: SalesPeriodComparison.empty(),
        trend: const [],
        previousTrend: const [],
        paymentBreakdown: const [],
        topProducts: const [],
        categorySales: const [],
        staffSummaries: const [],
        peakSalesPeriod: const PeakSalesPeriod(),
        sales: const [],
      );

  @override
  String toString() {
    return 'SalesAnalytics(${bounds.toString()}: $totalSales, $transactionCount txns, $itemsSold items)';
  }
}
