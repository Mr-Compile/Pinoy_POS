import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// A compact date-range selector: a dropdown of preset periods plus a
/// button that opens the platform date-range picker for custom ranges.
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
    ReportingPeriod.custom,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final dropdown = _buildDropdown(context);
        final button = AppButton.outlined(
          onPressed: onCustomRange == null ? null : () => _pickRange(context),
          icon: Icons.date_range,
          label: 'Custom',
          size: AppButtonSize.small,
          fullWidth: isCompact,
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dropdown,
              const SizedBox(height: Spacing.sm),
              button,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dropdown),
            const SizedBox(width: Spacing.sm),
            button,
          ],
        );
      },
    );
  }

  Widget _buildDropdown(BuildContext context) {
    return AppDropdown<ReportingPeriod>(
      label: 'Period',
      value: selected,
      items: _dropdownItems,
      onChanged: (value) {
        if (value == null) return;
        if (value == ReportingPeriod.custom) {
          _pickRange(context);
        } else {
          onSelected(value);
        }
      },
    );
  }

  List<DropdownMenuItem<ReportingPeriod>> get _dropdownItems {
    final items = _presetPeriods.map((period) {
      return DropdownMenuItem<ReportingPeriod>(
        value: period,
        child: Text(period.displayName),
      );
    }).toList();

    // If the parent passes a non-curated period, keep the dropdown valid
    // until the user picks a curated one.
    if (!_presetPeriods.contains(selected)) {
      items.add(
        DropdownMenuItem<ReportingPeriod>(
          value: selected,
          child: Text(selected.displayName),
        ),
      );
    }
    return items;
  }

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 365 * 2));
    final initial = customStart != null && customEnd != null
        ? DateTimeRange(start: customStart!, end: customEnd!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          );

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
}
