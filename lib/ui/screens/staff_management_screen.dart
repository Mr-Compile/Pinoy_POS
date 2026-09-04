import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/staff_provider.dart';
import 'package:pinoy_pos/services/staff_service.dart';
import 'package:pinoy_pos/services/user_service.dart';
import 'package:pinoy_pos/ui/screens/staff_detail_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Owner staff management screen.
///
/// Lists staff accounts, supports search, filters, sorting, and CRUD via
/// the [staffControllerProvider].
class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(staffControllerProvider.notifier).loadStaff();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      appBar: AppHeader(
        title: 'Staff Management',
        showBackButton: true,
      ),
      floatingActionButton: isTablet
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddStaffDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Staff'),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(staffControllerProvider.notifier).loadStaff(),
        child: Column(
          children: [
            _buildControls(context, state),
            Expanded(
              child: _buildBody(context, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, StaffListState state) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search by name or username',
            onChanged: (value) {
              ref.read(staffControllerProvider.notifier).setSearch(value);
            },
            onClear: () {
              _searchController.clear();
              ref.read(staffControllerProvider.notifier).setSearch('');
            },
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: state.filter == StaffFilter.all,
                        onSelected: () => ref
                            .read(staffControllerProvider.notifier)
                            .setFilter(StaffFilter.all),
                      ),
                      const SizedBox(width: Spacing.sm),
                      _FilterChip(
                        label: 'Active',
                        selected: state.filter == StaffFilter.active,
                        onSelected: () => ref
                            .read(staffControllerProvider.notifier)
                            .setFilter(StaffFilter.active),
                      ),
                      const SizedBox(width: Spacing.sm),
                      _FilterChip(
                        label: 'Inactive',
                        selected: state.filter == StaffFilter.inactive,
                        onSelected: () => ref
                            .read(staffControllerProvider.notifier)
                            .setFilter(StaffFilter.inactive),
                      ),
                    ],
                  ),
                ),
              ),
              _SortMenu(
                sortBy: state.sortBy,
                onSelected: (sort) => ref
                    .read(staffControllerProvider.notifier)
                    .setSort(sort),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                state.error!,
                style: AppTypography.bodySmall(context).copyWith(
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, StaffListState state) {
    if (state.isLoading && state.staff.isEmpty) {
      return const LoadingState(message: 'Loading staff...');
    }

    if (state.staff.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: 'No staff found',
        message: state.searchQuery.isEmpty
            ? 'Tap the + button to add your first staff member.'
            : 'Try adjusting your search or filters.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: state.staff.length,
      itemBuilder: (context, index) {
        final staff = state.staff[index];
        return _StaffListTile(
          staff: staff,
          onTap: () => _openStaffDetail(staff),
          onEdit: () => _showEditStaffDialog(staff),
          onResetPassword: () => _resetStaffPassword(staff),
          onToggleActive: () => _toggleStaffActive(staff),
          onDelete: () => _deleteStaff(staff),
        );
      },
    );
  }

  void _openStaffDetail(User staff) {
    if (staff.id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffDetailScreen(staffId: staff.id!),
      ),
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

  Future<void> _toggleStaffActive(User staff) async {
    final controller = ref.read(staffControllerProvider.notifier);
    if (staff.isActive) {
      final confirmed = await AppDialogService.confirmation(
        context,
        title: 'Deactivate Staff?',
        message: 'This will prevent ${staff.fullName} from logging in.',
        confirmLabel: 'Deactivate',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
      final result = await controller.deactivateStaff(staff.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(context,
              title: 'Done', message: result.message);
        } else {
          AppDialogService.error(context,
              title: 'Error', message: result.message);
        }
      }
    } else {
      final result = await controller.activateStaff(staff.id!);
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
        await AppDialogService.success(context,
            title: 'Done', message: result.message);
      } else {
        AppDialogService.error(context,
            title: 'Error', message: result.message);
      }
    }
  }

  void _showAddStaffDialog() => _showStaffDialog(null);

  void _showEditStaffDialog(User staff) => _showStaffDialog(staff);

  Future<void> _showStaffDialog(User? staff) async {
    final isEdit = staff != null;

    final result = await showDialog<ModalResult<void>>(
      context: context,
      builder: (context) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.info,
        title: isEdit ? 'Edit Staff' : 'Add Staff',
        childBuilder: (context, state) {
          final usernameController =
              state.textController('username', text: staff?.username ?? '');
          final fullNameController =
              state.textController('fullName', text: staff?.fullName ?? '');
          final pinController = state.textController('pin');

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEdit)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'A temporary password will be assigned. The staff member must change it on first login.',
                            style: AppTypography.bodySmall(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!isEdit) const SizedBox(height: Spacing.md),
                if (isEdit) ...[
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
                ],
                AppTextFormField(
                  controller: usernameController,
                  label: 'Username',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => state.markChanged(),
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  validator: (value) => Validators.required(value, 'Username'),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: fullNameController,
                  label: 'Full Name',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => state.markChanged(),
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  validator: (value) => Validators.required(value, 'Full Name'),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: pinController,
                  label: 'PIN (optional)',
                  hint: isEdit && staff.hasPin
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
            onPressed: (context) => state.pop(const ModalResult<void>.cancelled()),
          ),
          AppDialogAction(
            label: isEdit ? 'Save' : 'Add',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (context) => _saveStaff(state, staff, context),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == null || result.isCancelled) {
      return;
    }

    if (result.isSaved) {
      final message = isEdit
          ? 'Staff updated successfully'
          : 'Staff created successfully The temporary password is ${AppConstants.defaultTemporaryPassword}.';
      await AppDialogService.success(
        context,
        title: isEdit ? 'Updated' : 'Created',
        message: message,
      );
      if (mounted) {
        await _loadStaff();
      }
    } else if (result.isFailed) {
      await AppDialogService.error(
        context,
        title: 'Error',
        message: result.error ?? 'An unexpected error occurred.',
      );
    }
  }

  Future<void> _loadStaff() =>
      ref.read(staffControllerProvider.notifier).loadStaff();

  Future<void> _saveStaff(
    AppDialogFormState<ModalResult<void>> state,
    User? staff,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) {
      return;
    }

    state.setSaving(true);

    final username = state.textController('username').text.trim();
    final fullName = state.textController('fullName').text.trim();
    final pin = state.textController('pin').text.trim();

    final staffService = ref.read(staffServiceProvider);
    final UserOperationResult result;

    try {
      if (staff != null) {
        result = await staffService.updateStaff(
          staffId: staff.id!,
          username: username,
          fullName: fullName,
          pin: pin.isEmpty ? null : pin,
        );
      } else {
        result = await staffService.createStaff(
          username: username,
          fullName: fullName,
          pin: pin.isEmpty ? null : pin,
        );
      }
    } catch (e) {
      if (dialogContext.mounted) {
        state.setSaving(false);
        final message = e is AuthorizationException
            ? e.message
            : 'An unexpected error occurred. Please try again.';
        await AppDialogService.error(
          dialogContext,
          title: staff != null ? 'Update Failed' : 'Create Failed',
          message: message,
        );
      }
      return;
    }

    if (result.success) {
      state.pop(const ModalResult<void>.saved());
    } else {
      if (dialogContext.mounted) {
        state.setSaving(false);
        await AppDialogService.error(
          dialogContext,
          title: staff != null ? 'Update Failed' : 'Create Failed',
          message: result.message,
        );
      }
    }
  }
}

class _StaffListTile extends StatelessWidget {
  final User staff;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _StaffListTile({
    required this.staff,
    required this.onTap,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = staff.isActive
        ? AppSemanticColors.resolve(AppSemanticColors.success, cs.brightness)
        : AppSemanticColors.resolve(AppSemanticColors.neutral, cs.brightness);

    return AppListItem(
      leading: AppAvatar(
        imagePath: staff.profileImagePath,
        initials: staff.fullName.isNotEmpty
            ? staff.fullName[0].toUpperCase()
            : '?',
        radius: 24,
      ),
      title: staff.fullName,
      subtitle: '@${staff.username}',
      onTap: onTap,
      statusLabel: staff.isActive ? 'Active' : 'Inactive',
      statusColor: statusColor,
      actions: [
        AppListAction(
          icon: Icons.edit,
          tooltip: 'Edit',
          onPressed: onEdit,
        ),
        AppListAction(
          icon: Icons.lock_reset,
          tooltip: 'Reset Password',
          onPressed: onResetPassword,
        ),
        AppListAction(
          icon: staff.isActive ? Icons.person_off : Icons.person,
          tooltip: staff.isActive ? 'Deactivate' : 'Activate',
          color: staff.isActive
              ? AppSemanticColors.resolve(
                  AppSemanticColors.warning, cs.brightness)
              : AppSemanticColors.resolve(
                  AppSemanticColors.success, cs.brightness),
          onPressed: onToggleActive,
        ),
        AppListAction(
          icon: Icons.delete,
          tooltip: 'Delete',
          color: AppSemanticColors.resolve(
              AppSemanticColors.error, cs.brightness),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final StaffSortOrder sortBy;
  final ValueChanged<StaffSortOrder> onSelected;

  const _SortMenu({
    required this.sortBy,
    required this.onSelected,
  });

  static const _labels = <StaffSortOrder, String>{
    StaffSortOrder.nameAsc: 'Name A-Z',
    StaffSortOrder.nameDesc: 'Name Z-A',
    StaffSortOrder.usernameAsc: 'Username A-Z',
    StaffSortOrder.usernameDesc: 'Username Z-A',
    StaffSortOrder.createdAtDesc: 'Newest first',
    StaffSortOrder.createdAtAsc: 'Oldest first',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StaffSortOrder>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      onSelected: onSelected,
      itemBuilder: (context) => _labels.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Row(
                children: [
                  if (sortBy == e.key) ...[
                    Icon(Icons.check,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                  ] else
                    const SizedBox(width: 26),
                  Text(e.value),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
