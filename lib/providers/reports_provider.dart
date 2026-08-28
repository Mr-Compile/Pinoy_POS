import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/daily_sales_point.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/top_product_result.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/report_service.dart';

/// The selected report period type.
enum ReportPeriod { all, today, thisWeek, thisMonth, custom }

/// UI state for the Reports screen.
class ReportsState {
  final bool isLoading;
  final double todaySales;
  final double monthSales;
  final int lowStockCount;
  final int totalProducts;
  final int totalTransactions;
  final Settings storeInfo;
  final bool storeInfoIncomplete;
  final List<PaymentBreakdown> paymentBreakdown;
  final List<DailySalesPoint> dailySales;
  final List<TopProductResult> topProducts;
  final DateTime? filterStart;
  final DateTime? filterEnd;
  final String? error;

  ReportsState({
    this.isLoading = true,
    this.todaySales = 0.0,
    this.monthSales = 0.0,
    this.lowStockCount = 0,
    this.totalProducts = 0,
    this.totalTransactions = 0,
    required this.storeInfo,
    this.storeInfoIncomplete = false,
    this.paymentBreakdown = const [],
    this.dailySales = const [],
    this.topProducts = const [],
    this.filterStart,
    this.filterEnd,
    this.error,
  });

  ReportsState copyWith({
    bool? isLoading,
    double? todaySales,
    double? monthSales,
    int? lowStockCount,
    int? totalProducts,
    int? totalTransactions,
    Settings? storeInfo,
    bool? storeInfoIncomplete,
    List<PaymentBreakdown>? paymentBreakdown,
    List<DailySalesPoint>? dailySales,
    List<TopProductResult>? topProducts,
    DateTime? filterStart,
    DateTime? filterEnd,
    String? error,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      todaySales: todaySales ?? this.todaySales,
      monthSales: monthSales ?? this.monthSales,
      lowStockCount: lowStockCount ?? this.lowStockCount,
      totalProducts: totalProducts ?? this.totalProducts,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      storeInfo: storeInfo ?? this.storeInfo,
      storeInfoIncomplete: storeInfoIncomplete ?? this.storeInfoIncomplete,
      paymentBreakdown: paymentBreakdown ?? this.paymentBreakdown,
      dailySales: dailySales ?? this.dailySales,
      topProducts: topProducts ?? this.topProducts,
      filterStart: filterStart ?? this.filterStart,
      filterEnd: filterEnd ?? this.filterEnd,
      error: error ?? this.error,
    );
  }
}

/// Notifier that manages the Reports screen state.
///
/// Loads real data from [ReportService] and refreshes when the filter or
/// store information changes.  The UI never calls repositories directly.
class ReportsNotifier extends StateNotifier<ReportsState> {
  final Ref _ref;

  ReportsNotifier(this._ref)
      : super(ReportsState(
          storeInfo: Settings(
            storeName: 'Pinoy POS',
            currency: 'PHP',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        )) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final reportService = _ref.read(reportServiceProvider);
      final storeInfo = await reportService.getStoreInfo();
      final storeInfoIncomplete = await reportService.isStoreInfoIncomplete();

      final todaySales = await reportService.getTodaySales();
      final monthSales = await reportService.getMonthSales();
      final lowStockCount = await reportService.getLowStockCount();
      final totalProducts = await reportService.getTotalProducts();
      final totalTransactions = await reportService.getTotalTransactions();

      DateTime start;
      DateTime end;
      if (state.filterStart != null && state.filterEnd != null) {
        start = state.filterStart!;
        end = state.filterEnd!;
      } else {
        final now = DateTime.now();
        start = DateTime(now.year, now.month, 1);
        end = now;
      }

      final paymentBreakdown =
          await reportService.getPaymentBreakdown(start, end);
      final dailySales = await reportService.getDailySales(start, end);
      final topProducts = await reportService.getTopProducts(start, end);

      state = state.copyWith(
        isLoading: false,
        todaySales: todaySales,
        monthSales: monthSales,
        lowStockCount: lowStockCount,
        totalProducts: totalProducts,
        totalTransactions: totalTransactions,
        storeInfo: storeInfo,
        storeInfoIncomplete: storeInfoIncomplete,
        paymentBreakdown: paymentBreakdown,
        dailySales: dailySales,
        topProducts: topProducts,
      );
    } catch (e, st) {
      _log('load failed', e, st);
      state = state.copyWith(
        isLoading: false,
        error: 'Unable to load reports. Please try again.',
      );
    }
  }

  void setDateRange(DateTime start, DateTime end) {
    state = state.copyWith(filterStart: start, filterEnd: end);
    load();
  }

  void clearDateRange() {
    state = state.copyWith(filterStart: null, filterEnd: null);
    load();
  }

  Future<void> refreshStoreInfo() async {
    final reportService = _ref.read(reportServiceProvider);
    await reportService.refreshStoreInfo();
    await load();
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[ReportsNotifier] $message: $error\n$stackTrace');
    }
  }
}

final reportsProvider =
    StateNotifierProvider<ReportsNotifier, ReportsState>((ref) {
  return ReportsNotifier(ref);
});
