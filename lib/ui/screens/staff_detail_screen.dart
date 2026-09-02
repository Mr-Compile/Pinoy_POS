import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/staff_provider.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_section.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/payment_breakdown_list.dart';
import 'package:pinoy_pos/ui/widgets/period_selector.dart';
import 'package:pinoy_pos/ui/widgets/product_performance_list.dart';
import 'package:pinoy_pos/ui/widgets/sales_summary_cards.dart';
import 'package:pinoy_pos/ui/widgets/sales_transactions_list.dart';
import 'package:pinoy_pos/ui/widgets/sales_trend_chart.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Owner staff detail screen.
///
/// Shows the staff member's profile, sales analytics for a selected period,
/// recent transactions, and activity logs.
class StaffDetailScreen extends ConsumerStatefulWidget {
  final int staffId;

  const StaffDetailScreen({super.key, required this.staffId});

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffDetailProvider(widget.staffId));

    return Scaffold(
      appBar: AppHeader(
        title: 'Staff Details',
        showBackButton: true,
        actions: [
          if (state.staff != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _onMenuSelected(value, state.staff!),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset_password',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset, size: 20),
                      SizedBox(width: 8),
                      Text('Reset Password'),
                    ],
                  ),
                ),
                if (state.staff!.isActive)
                  const PopupMenuItem(
                    value: 'deactivate',
                    child: Row(
                      children: [
                        Icon(Icons.person_off, size: 20),
                        SizedBox(width: 8),
                        Text('Deactivate'),
                      ],
                    ),
                  )
                else
                  const PopupMenuItem(
                    value: 'activate',
                    child: Row(
                      children: [
                        Icon(Icons.person, size: 20),
                        SizedBox(width: 8),
                        Text('Activate'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, StaffDetailState state) {
    if (state.isLoading && state.staff == null) {
      return const LoadingState(message: 'Loading staff details...');
    }

    if (state.error != null) {
      return ErrorState(
        title: 'Unable to Load Staff Details',
        message: state.error,
        onRetry: () =>
            ref.read(staffDetailProvider(widget.staffId).notifier).load(),
      );
    }

    final staff = state.staff;
    if (staff == null) {
      return const ErrorState(
        title: 'Staff Not Found',
        message: 'The requested staff member could not be found.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(staffDetailProvider(widget.staffId).notifier).load(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildProfileCard(context, staff),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: PeriodSelector(
                selected: state.period,
                onSelected: (p) => ref
                    .read(staffDetailProvider(widget.staffId).notifier)
                    .selectPeriod(p),
                customStart: state.customStart,
                customEnd: state.customEnd,
                onCustomRange: (range) => ref
                    .read(staffDetailProvider(widget.staffId).notifier)
                    .setCustomRange(range.start, range.end),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildPeriodHeader(context, state),
            ),
            const SizedBox(height: Spacing.md),
            if (state.analytics != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: SalesSummaryCards(
                  analytics: state.analytics!,
                  storeInfo: state.storeInfo,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: AppSection(
                  title: 'Sales Trend',
                  subtitle: _trendSubtitle(state.analytics!.bounds),
                  child: SalesTrendChart(
                    trend: state.analytics!.trend,
                    groupBy: state.analytics!.bounds.groupBy,
                    valuePrefix: state.storeInfo?.currency,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: _ResponsiveTwoColumn(
                  left: AppSection(
                    title: 'Payment Methods',
                    child: PaymentBreakdownList(
                      breakdown: state.analytics!.paymentBreakdown,
                      grandTotal: state.analytics!.totalSales,
                      storeInfo: state.storeInfo,
                    ),
                  ),
                  right: AppSection(
                    title: 'Top Products',
                    child: ProductPerformanceList(
                      products: state.analytics!.topProducts,
                      storeInfo: state.storeInfo,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: AppSection(
                  title: 'Recent Transactions',
                  subtitle: 'Confirmed sales for the selected period',
                  child: SalesTransactionsList(
                    sales: state.analytics!.sales,
                    storeInfo: state.storeInfo,
                    onTap: _openSale,
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: AppSection(
                title: 'Activity Log',
                child: _ActivityLogList(
                  logs: state.activityLogs,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, User staff) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = staff.isActive
        ? AppSemanticColors.resolve(AppSemanticColors.success, cs.brightness)
        : AppSemanticColors.resolve(AppSemanticColors.neutral, cs.brightness);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            imagePath: staff.profileImagePath,
            initials: staff.fullName.isNotEmpty
                ? staff.fullName[0].toUpperCase()
                : '?',
            radius: 36,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.fullName,
                  style: AppTypography.headlineSmallSemibold(context),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '@${staff.username}',
                  style: AppTypography.bodyMedium(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  children: [
                    AppStatusChip(
                      label: staff.isActive ? 'Active' : 'Inactive',
                      color: statusColor,
                      icon: staff.isActive ? Icons.check_circle : Icons.cancel,
                    ),
                    AppStatusChip(
                      label: 'Staff',
                      color: cs.primary,
                      filled: false,
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Created on ${DateFormat.yMd().format(staff.createdAt)}',
                  style: AppTypography.bodySmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodHeader(BuildContext context, StaffDetailState state) {
    final analytics = state.analytics;
    final label = state.period.displayName;
    final bounds = analytics?.bounds;
    final rangeText = bounds != null
        ? '${DateFormat.yMd().format(bounds.start)} - ${DateFormat.yMd().format(bounds.end.subtract(const Duration(milliseconds: 1)))}'
        : '';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.titleMediumBold(context),
        ),
        if (rangeText.isNotEmpty)
          Text(
            rangeText,
            style: AppTypography.bodySmall(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  String _trendSubtitle(ReportingPeriodBounds bounds) {
    return switch (bounds.groupBy) {
      ReportGroupBy.hour => 'Hourly',
      ReportGroupBy.day => 'Daily',
      ReportGroupBy.week => 'Weekly',
      ReportGroupBy.month => 'Monthly',
    };
  }

  void _openSale(Sale sale) {
    if (sale.id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(saleId: sale.id!),
      ),
    );
  }

  Future<void> _onMenuSelected(String value, User staff) async {
    switch (value) {
      case 'edit':
        await _showEditStaffDialog(staff);
      case 'reset_password':
        await _resetStaffPassword(staff);
      case 'activate':
        await _activateStaff(staff);
      case 'deactivate':
        await _deactivateStaff(staff);
      case 'delete':
        await _deleteStaff(staff);
    }
  }

  Future<void> _resetStaffPassword(User staff) async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Reset Password?',
      message:
          'This will reset the password for ${staff.fullName} (@${staff.username}) to the default temporary password.',
      confirmLabel: 'Reset',
    );
    if (confirmed != true && mounted) return;

    final result = await ref
        .read(staffControllerProvider.notifier)
        .resetPassword(staff.id!);
    if (mounted) {
      if (result.success) {
        await AppDialogService.success(context,
            title: 'Done', message: result.message);
      } else {
        AppDialogService.error(context,
            title: 'Error', message: result.message);
      }
    }
  }

  Future<void> _activateStaff(User staff) async {
    final result =
        await ref.read(staffControllerProvider.notifier).activateStaff(staff.id!);
    if (!mounted) return;
    if (result.success) {
      await ref.read(staffDetailProvider(widget.staffId).notifier).load();
      if (!mounted) return;
      await AppDialogService.success(context,
          title: 'Done', message: result.message);
    } else {
      AppDialogService.error(context,
          title: 'Error', message: result.message);
    }
  }

  Future<void> _deactivateStaff(User staff) async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Deactivate Staff?',
      message: 'This will prevent ${staff.fullName} from logging in.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(staffControllerProvider.notifier)
        .deactivateStaff(staff.id!);
    if (!mounted) return;
    if (result.success) {
      await ref.read(staffDetailProvider(widget.staffId).notifier).load();
      if (!mounted) return;
      await AppDialogService.success(context,
          title: 'Done', message: result.message);
    } else {
      AppDialogService.error(context,
          title: 'Error', message: result.message);
    }
  }

  Future<void> _deleteStaff(User staff) async {
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: '${staff.fullName} (@${staff.username})',
      permanent: false,
    );
    if (confirmed != true || !mounted) return;

    final result =
        await ref.read(staffControllerProvider.notifier).softDeleteStaff(staff.id!);
    if (mounted) {
      if (result.success) {
        Navigator.of(context).maybePop();
      } else {
        AppDialogService.error(context,
            title: 'Error', message: result.message);
      }
    }
  }

  Future<void> _showEditStaffDialog(User staff) async {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: staff.username);
    final fullNameController = TextEditingController(text: staff.fullName);
    final pinController = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          type: AppDialogType.info,
          title: 'Edit Staff',
          actions: [
            AppDialogAction(
              label: 'Cancel',
              onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
            ),
            AppDialogAction(
              label: 'Save',
              isPrimary: true,
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : (context) async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => isSaving = true);

                      final pinValue = pinController.text.trim();
                      final result = await ref
                          .read(staffControllerProvider.notifier)
                          .updateStaff(
                            staffId: staff.id!,
                            username: usernameController.text.trim(),
                            fullName: fullNameController.text.trim(),
                            pin: pinValue.isEmpty ? null : pinValue,
                          );

                      if (context.mounted) {
                        setState(() => isSaving = false);
                      }

                      if (result.success) {
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).pop();
                          await AppDialogService.success(
                            context,
                            title: 'Updated',
                            message: result.message,
                          );
                          await ref
                              .read(staffDetailProvider(widget.staffId).notifier)
                              .load();
                        }
                      } else {
                        if (context.mounted) {
                          AppDialogService.error(
                            context,
                            title: 'Update Failed',
                            message: result.message,
                          );
                        }
                      }
                    },
            ),
          ],
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    validator: (value) => Validators.required(value, 'Username'),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => Validators.required(value, 'Full Name'),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: pinController,
                    decoration: InputDecoration(
                      labelText: 'PIN (optional)',
                      border: const OutlineInputBorder(),
                      hintText: staff.hasPin
                          ? 'Enter new PIN to replace (${staff.configuredPinLength} digits)'
                          : '4-6 digits',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityLogList extends StatelessWidget {
  final List<ActivityLog> logs;

  const _ActivityLogList({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No activity',
        message: 'No activity logs for this staff member yet.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < logs.length; i++) ...[
          _ActivityLogRow(log: logs[i]),
          if (i < logs.length - 1) const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

class _ActivityLogRow extends StatelessWidget {
  final ActivityLog log;

  const _ActivityLogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Icon(
              Icons.history,
              size: 18,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.action,
                  style: AppTypography.titleMediumSemibold(context),
                ),
                if (log.details != null && log.details!.isNotEmpty)
                  Text(
                    log.details!,
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  _formatDate(log.createdAt),
                  style: AppTypography.labelSmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return DateFormat.yMd().add_jm().format(d);
  }
}

class _ResponsiveTwoColumn extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsiveTwoColumn({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    if (!isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          left,
          const SizedBox(height: Spacing.lg),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: Spacing.lg),
        Expanded(child: right),
      ],
    );
  }
}
