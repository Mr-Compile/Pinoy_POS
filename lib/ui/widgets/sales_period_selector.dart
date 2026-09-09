import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/date_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/providers/sales_period_filter_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// Collapsed period selector matching the dashboard mockup.
///
/// Renders a segmented Daily / Weekly / Monthly bar with a calendar toggle,
/// followed by a `‹ date ›` navigator row. The full calendar and the custom
/// range controls stay hidden until the calendar icon is tapped (or a custom
/// range is active), keeping the dashboard compact by default.
///
/// The selected date is stored in [salesPeriodFilterProvider] so the
/// Dashboard and Sales Analytics screens share the same filter.
class SalesPeriodSelector extends ConsumerStatefulWidget {
  const SalesPeriodSelector({super.key});

  @override
  ConsumerState<SalesPeriodSelector> createState() =>
      _SalesPeriodSelectorState();
}

class _SalesPeriodSelectorState extends ConsumerState<SalesPeriodSelector> {
  bool _pickerExpanded = false;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(salesPeriodFilterProvider);
    final notifier = ref.read(salesPeriodFilterProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, now.month, 1);
    final lastDate = now.add(const Duration(days: 365));
    final isCustom = filter.period == SalesPeriod.custom;
    final showPicker = _pickerExpanded || isCustom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segmented period bar + calendar toggle.
        Row(
          children: [
            Expanded(
              child: SegmentedButton<SalesPeriod>(
                multiSelectionEnabled: false,
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                selected:
                    isCustom ? const {} : {filter.period},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    notifier.selectPeriod(selected.first);
                  }
                },
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
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
            const SizedBox(width: Spacing.sm),
            _CalendarToggle(
              expanded: showPicker,
              onTap: () => setState(() => _pickerExpanded = !_pickerExpanded),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        // ‹ date › navigator bar.
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs,
            vertical: 2,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: isCustom ? null : () => notifier.moveByStep(-1),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  formatSalesPeriodLabel(filter),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: isCustom ? null : () => notifier.moveByStep(1),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // Expanded picker area: calendar for fixed periods, custom range
        // controls when a custom range is selected.
        if (showPicker) ...[
          const SizedBox(height: Spacing.sm),
          if (isCustom)
            _buildCustomRangeCard(context, filter, notifier)
          else
            Column(
              children: [
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
                      onDateChanged: (date) {
                        notifier.selectDate(startOfDay(date));
                        setState(() => _pickerExpanded = false);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: notifier.today,
                      icon: const Icon(Icons.today, size: 18),
                      label: const Text('Today'),
                    ),
                    const SizedBox(width: Spacing.sm),
                    AppButton.outlined(
                      onPressed: () =>
                          _pickCustomRange(context, filter, notifier),
                      icon: Icons.date_range,
                      label: 'Custom',
                      size: AppButtonSize.small,
                    ),
                  ],
                ),
              ],
            ),
        ],
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
                  'Custom',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              formatSalesPeriodLabel(filter),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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

/// The 36x36 calendar toggle button from the mockup's period bar.
class _CalendarToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _CalendarToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: expanded ? cs.primary : cs.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: expanded ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
