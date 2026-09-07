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
                  ButtonSegment(
                    value: SalesPeriod.custom,
                    label: Text('Range'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        // Calendar for fixed periods, range picker for custom.
        if (filter.period == SalesPeriod.custom)
          _buildCustomRangeCard(context, filter, notifier)
        else
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            color: cs.surface,
            child: Localizations.override(
              context: context,
              locale: const Locale('en', 'US'),
              child: CalendarDatePicker(
                key: ValueKey(filter),
                initialDate: filter.selectedDate,
                firstDate: firstDate,
                lastDate: lastDate,
                currentDate: now,
                onDateChanged: (date) => notifier.selectDate(startOfDay(date)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCustomRangeCard(
    BuildContext context,
    SalesPeriodFilter filter,
    SalesPeriodFilterNotifier notifier,
  ) {
    final cs = Theme.of(context).colorScheme;
    final start = filter.selectedDate;
    final end = filter.customEnd ?? start;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatSalesPeriodLabel(filter),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            ElevatedButton.icon(
              onPressed: () => _pickCustomRange(context, filter, notifier),
              icon: const Icon(Icons.date_range, size: 18),
              label: const Text('Choose date range'),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              '${_shortDate(start)} – ${_shortDate(end)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<void> _pickCustomRange(
    BuildContext context,
    SalesPeriodFilter filter,
    SalesPeriodFilterNotifier notifier,
  ) async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: filter.selectedDate,
      end: filter.customEnd ?? filter.selectedDate,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, now.month, 1),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: Theme.of(context).appBarTheme.copyWith(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      notifier.setCustomRange(picked.start, picked.end);
    }
  }
}
