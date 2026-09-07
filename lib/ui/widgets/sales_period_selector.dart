import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';

/// Calendar-based period selector used by the Dashboard and Sales Analytics
/// screens.
///
/// Provides Daily / Weekly / Monthly granularity, a month calendar, previous /
/// next period navigation, and a Today shortcut. The selected date is stored in
/// [salesPeriodFilterProvider] so both screens share the same filter.
class SalesPeriodSelector extends ConsumerStatefulWidget {
  const SalesPeriodSelector({super.key});

  @override
  ConsumerState<SalesPeriodSelector> createState() =>
      _SalesPeriodSelectorState();
}

class _SalesPeriodSelectorState extends ConsumerState<SalesPeriodSelector> {
  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(salesPeriodFilterProvider);
    final notifier = ref.read(salesPeriodFilterProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, now.month, 1);
    final lastDate = now.add(const Duration(days: 365));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period label and navigation
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => notifier.moveByStep(-1),
            ),
            Expanded(
              child: Text(
                formatSalesPeriodLabel(filter),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => notifier.moveByStep(1),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        // Today shortcut
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: notifier.today,
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        // Granularity toggles
        Row(
          children: [
            Expanded(
              child: SegmentedButton<SalesPeriod>(
                multiSelectionEnabled: false,
                emptySelectionAllowed: false,
                selected: {filter.period},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    notifier.selectPeriod(selected.first);
                  }
                },
                segments: const [
                  ButtonSegment(
                    value: SalesPeriod.daily,
                    label: Text('Daily'),
                  ),
                  ButtonSegment(
                    value: SalesPeriod.weekly,
                    label: Text('Weekly'),
                  ),
                  ButtonSegment(
                    value: SalesPeriod.monthly,
                    label: Text('Monthly'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        // Calendar
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          color: cs.surface,
          child: CalendarDatePicker(
            key: ValueKey(filter),
            initialDate: filter.selectedDate,
            firstDate: firstDate,
            lastDate: lastDate,
            currentDate: now,
            onDateChanged: (date) => notifier.selectDate(startOfDay(date)),
          ),
        ),
      ],
    );
  }
}
