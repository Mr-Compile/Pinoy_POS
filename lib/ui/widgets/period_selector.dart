import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';

/// A horizontally scrollable row of period chips with a "Custom" action that
/// opens the platform date-range picker.
class PeriodSelector extends StatelessWidget {
  final ReportingPeriod selected;
  final ValueChanged<ReportingPeriod> onSelected;
  final DateTime? customStart;
  final DateTime? customEnd;
  final ValueChanged<DateTimeRange>? onCustomRange;

  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.customStart,
    this.customEnd,
    this.onCustomRange,
  });

  static const List<ReportingPeriod> _presetPeriods = [
    ReportingPeriod.today,
    ReportingPeriod.yesterday,
    ReportingPeriod.thisWeek,
    ReportingPeriod.lastWeek,
    ReportingPeriod.thisMonth,
    ReportingPeriod.lastMonth,
    ReportingPeriod.thisYear,
    ReportingPeriod.lastYear,
    ReportingPeriod.last7Days,
    ReportingPeriod.last30Days,
    ReportingPeriod.last90Days,
    ReportingPeriod.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          for (final period in _presetPeriods)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: period == ReportingPeriod.custom
                  ? _buildCustomChip(context, cs)
                  : ChoiceChip(
                      label: Text(period.shortName),
                      selected: period == selected,
                      onSelected: (_) => onSelected(period),
                      selectedColor: cs.primaryContainer,
                      backgroundColor: cs.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        color: period == selected
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                        fontWeight: period == selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomChip(BuildContext context, ColorScheme cs) {
    final isSelected = selected == ReportingPeriod.custom;
    final label = isSelected && customStart != null && customEnd != null
        ? '${_shortDate(customStart!)} - ${_shortDate(customEnd!)}'
        : 'Custom';

    return ActionChip(
      avatar: Icon(
        Icons.date_range,
        size: 18,
        color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
      ),
      label: Text(label),
      backgroundColor:
          isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
      side: isSelected ? BorderSide.none : null,
      labelStyle: TextStyle(
        color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onPressed: () => _pickRange(context),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 365 * 2));
    final initial = customStart != null && customEnd != null
        ? DateTimeRange(
            start: customStart!,
            end: customEnd!,
          )
        : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: initial,
    );

    if (picked != null && onCustomRange != null) {
      onCustomRange!(picked);
    }
  }

  String _shortDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
