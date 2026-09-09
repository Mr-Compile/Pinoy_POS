import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/staff_provider.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
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
      appBar: const AppHeader(title: 'Staff Details', showBackButton: true),
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
      onRefresh: () =>
          ref.read(staffDetailProvider(widget.staffId).notifier).load(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildStatusBanner(context, staff),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildOverviewCard(context, staff),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: _buildActionBar(context, staff),
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
                  child: SalesTrendChart(
                    trend: state.analytics!.trend,
                    groupBy: state.analytics!.bounds.groupBy,
                    valuePrefix: CurrencyUtils.symbol(
                      currency: state.storeInfo?.currency,
                    ),
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
                child: _ActivityLogList(logs: state.activityLogs),
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, User staff) {
    final deactivateButton = staff.isActive
        ? AppButton.outlined(
            icon: Icons.person_off,
            label: 'Deactivate',
            color: AppButtonColor.warning,
            fullWidth: true,
            onPressed: () => _deactivateStaff(staff),
          )
        : AppButton.outlined(
            icon: Icons.person,
            label: 'Activate',
            color: AppButtonColor.success,
            fullWidth: true,
            onPressed: () => _activateStaff(staff),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton.filled(
                icon: Icons.edit,
                label: 'Edit',
                fullWidth: true,
                onPressed: () => _showEditStaffDialog(staff),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: AppButton.outlined(
                icon: Icons.lock_reset,
                label: 'Reset Password',
                fullWidth: true,
                onPressed: () => _resetStaffPassword(staff),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            Expanded(child: deactivateButton),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: AppButton.outlined(
                icon: Icons.delete,
                label: 'Delete',
                color: AppButtonColor.error,
                fullWidth: true,
                onPressed: () => _deleteStaff(staff),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Status banner ───────────────────────────────────────────

  Widget _buildStatusBanner(BuildContext context, User staff) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isActive = staff.isActive;
    final statusColor = isActive
        ? AppSemanticColors.resolve(AppSemanticColors.success, brightness)
        : AppSemanticColors.resolve(AppSemanticColors.neutral, brightness);
    final onStatusColor = AppSemanticColors.contrastFor(statusColor, brightness);

    return AppCard(
      color: statusColor.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.check : Icons.cancel,
              color: onStatusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isActive ? 'Active' : 'Inactive',
                  style: AppTypography.titleMediumBold(context).copyWith(
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lastLoginText(staff),
                  style: AppTypography.bodySmall(context).copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          AppStatusChip(
            label: staff.role.displayName,
            color: cs.primary,
            icon: Icons.badge_outlined,
          ),
        ],
      ),
    );
  }

  String _lastLoginText(User staff) {
    final lastLogin = staff.lastLogin;
    if (lastLogin == null) {
      return 'Never logged in';
    }
    return 'Last login: ${DateFormat.yMd().add_jm().format(lastLogin)}';
  }

  // ── Overview card (avatar + 4 icon tiles) ──────────────────

  Widget _buildOverviewCard(BuildContext context, User staff) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                imagePath: staff.profileImagePath,
                initials: staff.fullName.isNotEmpty
                  ? staff.fullName[0].toUpperCase()
                  : '?',
                radius: 40,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      staff.fullName,
                      style: AppTypography.headlineSmallSemibold(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${staff.username}',
                      style: AppTypography.bodyMedium(
                        context,
                      ).copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const Divider(height: 1),
          const SizedBox(height: Spacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.md,
            crossAxisSpacing: Spacing.md,
            childAspectRatio: 2.2,
            children: [
              _buildOverviewTile(
                icon: Icons.person_outline,
                color: cs.primary,
                label: 'Role',
                value: staff.role.displayName,
              ),
              _buildOverviewTile(
                icon: Icons.alternate_email,
                color: AppSemanticColors.resolve(
                  AppSemanticColors.purple,
                  brightness,
                ),
                label: 'Username',
                value: '@${staff.username}',
              ),
              _buildOverviewTile(
                icon: Icons.calendar_today_outlined,
                color: AppSemanticColors.resolve(
                  AppSemanticColors.warning,
                  brightness,
                ),
                label: 'Joined',
                value: DateFormat.yMd().format(staff.createdAt),
              ),
              _buildOverviewTile(
                icon: Icons.history,
                color: AppSemanticColors.resolve(
                  AppSemanticColors.success,
                  brightness,
                ),
                label: 'Last login',
                value: staff.lastLogin == null
                    ? 'Never'
                    : DateFormat.yMd().add_jm().format(staff.lastLogin!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.bodyMediumSemibold(context).copyWith(
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
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
        Text(label, style: AppTypography.titleMediumBold(context)),
        if (rangeText.isNotEmpty)
          Text(
            rangeText,
            style: AppTypography.bodySmall(
              context,
            ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  void _openSale(Sale sale) {
    if (sale.id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id!)),
    );
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
        await AppDialogService.success(
          context,
          title: 'Done',
          message: result.message,
        );
      } else {
        AppDialogService.error(
          context,
          title: 'Error',
          message: result.message,
        );
      }
    }
  }

  Future<void> _activateStaff(User staff) async {
    final result = await ref
        .read(staffControllerProvider.notifier)
        .activateStaff(staff.id!);
    if (!mounted) return;
    if (result.success) {
      await ref.read(staffDetailProvider(widget.staffId).notifier).load();
      if (!mounted) return;
      await AppDialogService.success(
        context,
        title: 'Done',
        message: result.message,
      );
    } else {
      AppDialogService.error(context, title: 'Error', message: result.message);
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
      await AppDialogService.success(
        context,
        title: 'Done',
        message: result.message,
      );
    } else {
      AppDialogService.error(context, title: 'Error', message: result.message);
    }
  }

  Future<void> _deleteStaff(User staff) async {
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: '${staff.fullName} (@${staff.username})',
      permanent: false,
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(staffControllerProvider.notifier)
        .softDeleteStaff(staff.id!);
    if (mounted) {
      if (result.success) {
        Navigator.of(context).maybePop();
      } else {
        AppDialogService.error(
          context,
          title: 'Error',
          message: result.message,
        );
      }
    }
  }

  Future<void> _showEditStaffDialog(User staff) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.edit,
        title: 'Edit Staff',
        childBuilder: (context, state) {
          final usernameController = state.textController(
            'username',
            text: staff.username,
          );
          final fullNameController = state.textController(
            'fullName',
            text: staff.fullName,
          );
          final pinController = state.textController('pin');

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: AppAvatar(
                    imagePath: staff.profileImagePath,
                    initials: staff.fullName.isNotEmpty
                        ? staff.fullName[0].toUpperCase()
                        : '?',
                    radius: 40,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: usernameController,
                  label: 'Username',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => state.markChanged(),
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  validator: (value) => Validators.required(value, 'Username'),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: fullNameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => state.markChanged(),
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  validator: (value) => Validators.required(value, 'Full Name'),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: pinController,
                  label: 'PIN (optional)',
                  prefixIcon: Icons.lock_outline,
                  hint: staff.hasPin
                      ? 'Enter new PIN to replace (${staff.configuredPinLength} digits)'
                      : '4-6 digits',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => state.markChanged(),
                  onFieldSubmitted: (_) => _saveStaff(state, staff, context),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return Validators.pin(value);
                  },
                ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: state.isSaving
                ? null
                : (dialogContext) async {
                    if (state.hasChanges) {
                      final discard = await AppDialogService.unsavedChanges(
                        dialogContext,
                      );
                      if (discard == true && dialogContext.mounted) {
                        state.pop(const ModalResult<void>.cancelled());
                      }
                    } else if (dialogContext.mounted) {
                      state.pop(const ModalResult<void>.cancelled());
                    }
                  },
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (dialogContext) async {
                    await _saveStaff(state, staff, dialogContext);
                  },
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result?.isSaved == true) {
      await AppDialogService.success(
        context,
        title: 'Updated',
        message: 'Staff updated successfully',
      );
      await ref.read(staffDetailProvider(widget.staffId).notifier).load();
    } else if (result?.isFailed == true) {
      AppDialogService.error(
        context,
        title: 'Update Failed',
        message: result?.error ?? 'An error occurred while updating staff.',
      );
    }
  }

  Future<void> _saveStaff(
    AppDialogFormState<ModalResult<void>> state,
    User staff,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) return;

    state.setSaving(true);

    final pinValue = state.textController('pin').text.trim();
    final result = await ref
        .read(staffControllerProvider.notifier)
        .updateStaff(
          staffId: staff.id!,
          username: state.textController('username').text.trim(),
          fullName: state.textController('fullName').text.trim(),
          pin: pinValue.isEmpty ? null : pinValue,
        );

    if (result.success) {
      state.pop(const ModalResult<void>.saved());
    } else {
      state.setSaving(false);
      if (dialogContext.mounted) {
        AppDialogService.error(
          dialogContext,
          title: 'Update Failed',
          message: result.message,
        );
      }
    }
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
            child: Icon(Icons.history, size: 18, color: cs.onPrimaryContainer),
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
                    style: AppTypography.bodySmall(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  _formatDate(log.createdAt),
                  style: AppTypography.labelSmall(
                    context,
                  ).copyWith(color: cs.onSurfaceVariant),
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
    final isTablet =
        layoutClassFor(MediaQuery.of(context).size.width).isAtLeastMedium;

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
