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
    state = state.copyWith(
      period: period,
      clearCustomEnd: period != SalesPeriod.custom,
    );
  }

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: startOfDay(date),
      clearCustomEnd: true,
    );
  }

  void today() {
    state = state.copyWith(
      selectedDate: startOfDay(DateTime.now()),
      clearCustomEnd: true,
    );
  }

  /// Sets a custom start/end date range.
  void setCustomRange(DateTime start, DateTime end) {
    final normalizedStart = startOfDay(start);
    final normalizedEnd = startOfDay(end);
    state = state.copyWith(
      period: SalesPeriod.custom,
      selectedDate: normalizedStart,
      customEnd:
          normalizedEnd.isBefore(normalizedStart) ? normalizedStart : normalizedEnd,
    );
  }

  /// Moves the selected period one step forward ([step] = 1) or backward
  /// ([step] = -1) along the current [period] granularity.
  /// Custom ranges do not support stepping.
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
      case SalesPeriod.custom:
        return;
    }
    state = state.copyWith(
      selectedDate: startOfDay(next),
      clearCustomEnd: true,
    );
  }
}

final salesPeriodFilterProvider =
    StateNotifierProvider<SalesPeriodFilterNotifier, SalesPeriodFilter>((ref) {
  return SalesPeriodFilterNotifier();
});
