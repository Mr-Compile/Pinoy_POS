import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

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
        if (filter.period != SalesPeriod.custom)
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
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Center(
              child: Text(
                formatSalesPeriodLabel(filter),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        // Today shortcut
        if (filter.period != SalesPeriod.custom)
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
        // Granularity toggles + Custom button, matching the sales screen
        // PeriodSelector layout.
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 360;
            final toggles = SegmentedButton<SalesPeriod>(
              multiSelectionEnabled: false,
              emptySelectionAllowed: true,
              selected: filter.period == SalesPeriod.custom
                  ? const {}
                  : {filter.period},
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
            );
            final customButton = AppButton.outlined(
              onPressed: () => _pickCustomRange(context, filter, notifier),
              icon: Icons.date_range,
              label: 'Custom',
              size: AppButtonSize.small,
              fullWidth: isCompact,
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toggles,
                  const SizedBox(height: Spacing.sm),
                  customButton,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: toggles),
                const SizedBox(width: Spacing.sm),
                customButton,
              ],
            );
          },
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
            AppButton.outlined(
              onPressed: () => _pickCustomRange(context, filter, notifier),
              icon: Icons.date_range,
              label: 'Choose date range',
              size: AppButtonSize.small,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              filter.customEnd != null
                  ? '${_shortDate(start)} – ${_shortDate(end)}'
                  : 'Choose a date range',
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
    final today = startOfDay(now);
    final first = today.subtract(const Duration(days: 365 * 2));
    final last = today.add(const Duration(days: 1));

    final initial = filter.customEnd != null
        ? DateTimeRange(
            start: filter.selectedDate,
            end: filter.customEnd!,
          )
        : DateTimeRange(
            start: today.subtract(const Duration(days: 30)),
            end: today,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: Theme.of(context).appBarTheme.copyWith(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
          ),
          child: Localizations.override(
            context: context,
            locale: const Locale('en', 'US'),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      notifier.setCustomRange(picked.start, picked.end);
    }
  }
}
