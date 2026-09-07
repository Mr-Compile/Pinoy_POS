import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';

/// Shared calendar-based filter for Dashboard and Sales Analytics.
///
/// Both screens watch the same provider so the selected period and date
/// are always identical and all analytics are produced by the same rules.
class SalesPeriodFilterNotifier extends StateNotifier<SalesPeriodFilter> {
  SalesPeriodFilterNotifier()
      : super(SalesPeriodFilter(
          period: SalesPeriod.monthly,
          selectedDate: startOfDay(DateTime.now()),
        ));

  void selectPeriod(SalesPeriod period) {
    state = state.copyWith(period: period);
  }

  void selectDate(DateTime date) {
    state = state.copyWith(selectedDate: startOfDay(date));
  }

  void today() {
    state = state.copyWith(selectedDate: startOfDay(DateTime.now()));
  }

  /// Moves the selected period one step forward ([step] = 1) or backward
  /// ([step] = -1) along the current [period] granularity.
  void moveByStep(int step) {
    final selected = state.selectedDate;
    late final DateTime next;
    switch (state.period) {
      case SalesPeriod.daily:
        next = selected.add(Duration(days: step));
      case SalesPeriod.weekly:
        next = selected.add(Duration(days: 7 * step));
      case SalesPeriod.monthly:
        final targetYear = selected.year + (selected.month + step - 1) ~/ 12;
        final targetMonth = (selected.month + step - 1) % 12 + 1;
        final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
        next = DateTime(
          targetYear,
          targetMonth,
          selected.day.clamp(1, lastDay),
        );
    }
    state = state.copyWith(selectedDate: startOfDay(next));
  }
}

final salesPeriodFilterProvider =
    StateNotifierProvider<SalesPeriodFilterNotifier, SalesPeriodFilter>((ref) {
  return SalesPeriodFilterNotifier();
});
