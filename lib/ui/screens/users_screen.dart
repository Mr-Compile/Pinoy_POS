import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  UserRole? _roleFilter;

  @override
  void initState() {
    super.initState();
    // Load users from SQLite via the controller on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userControllerProvider.notifier).loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<User> _filterUsers(List<User> users) {
    var filtered = users;
    if (_roleFilter != null) {
      filtered = filtered.where((u) => u.role == _roleFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        return u.username.toLowerCase().contains(query) ||
            u.fullName.toLowerCase().contains(query);
      }).toList();
    }
    return filtered;
  }

  Color _roleColor(UserRole role, ColorScheme colorScheme) {
    final brightness = Theme.of(context).brightness;
    return switch (role) {
      UserRole.owner =>
        AppSemanticColors.resolve(AppSemanticColors.primary, brightness),
      UserRole.admin =>
        AppSemanticColors.resolve(AppSemanticColors.purple, brightness),
      UserRole.staff =>
        AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
    };
  }

  Future<void> _refresh() async {
    await ref.read(userControllerProvider.notifier).loadUsers();
  }

  // ── DELETE (soft) ────────────────────────────────────────────────────

  Future<void> _deleteUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_users')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final currentUser = ref.read(authStateProvider).user;
    if (currentUser?.id == user.id) {
      AppDialogService.warning(context, title: 'Action Not Allowed', message: 'You cannot delete your own account.');
      return;
    }

    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: '${user.fullName} (@${user.username})',
      permanent: false,
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(userControllerProvider.notifier)
          .softDeleteUser(user.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(context, title: 'Done', message: result.message);
        } else {
          AppDialogService.error(context, title: 'Error', message: result.message);
        }
      }
    }
  }

  // ── ACTIVATE / DEACTIVATE ────────────────────────────────────────────

  Future<void> _toggleUserActive(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('toggle_user_active')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final currentUser = ref.read(authStateProvider).user;
    if (currentUser?.id == user.id && user.isActive) {
      AppDialogService.warning(context, title: 'Action Not Allowed', message: 'You cannot deactivate your own account.');
      return;
    }

    if (user.isActive) {
      // Confirm deactivation.
      final confirmed = await AppDialogService.deactivateUserConfirm(
        context,
        userName: user.fullName,
      );
      if (confirmed != true || !mounted) return;
      final result = await ref
          .read(userControllerProvider.notifier)
          .deactivateUser(user.id!);
      if (mounted) {
        await AppDialogService.success(context, title: 'Done', message: result.message);
      }
    } else {
      // Activate directly.
      final result = await ref
          .read(userControllerProvider.notifier)
          .activateUser(user.id!);
      if (mounted) {
        await AppDialogService.success(context, title: 'Done', message: result.message);
      }
    }
  }

  // ── RESET PASSWORD ───────────────────────────────────────────────────

  Future<void> _resetPassword(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('reset_password')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Reset Password?',
      message:
          'This will reset the password for ${user.fullName} (@${user.username}) to the default temporary password.',
      details: 'The user will be required to change it on next login.',
      confirmLabel: 'Reset',
      destructive: true,
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(userControllerProvider.notifier)
          .resetPassword(user.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Password Reset',
            message: result.message,
          );
        } else {
          AppDialogService.error(
            context,
            title: 'Reset Failed',
            message: result.message,
          );
        }
      }
    }
  }

  // ── EDIT USER ────────────────────────────────────────────────────────

  Future<void> _editUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('edit_users')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final currentUser = ref.read(authStateProvider).user;
    final manageableRoles =
        UserRoleManagement.manageableBy(currentUser?.role ?? UserRole.staff);
    final roleItems = manageableRoles.contains(user.role)
        ? manageableRoles
        : [user.role, ...manageableRoles];

    // Clear any stale error before opening the dialog so a previous failure
    // is not shown again if the user opens a different user.
    ref.read(userControllerProvider.notifier).clearError();

    final result = await showDialog<ModalResult<void>>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.edit,
        title: 'Edit User: ${user.username}',
        canPop: false,
        onPopInvokedWithResult: (context, state, didPop, result) {
          if (!didPop && !state.isSaving) {
            _confirmCancelEdit(state, dialogContext);
          }
        },
        childBuilder: (context, state) {
          final usernameController = state.textController('username', text: user.username);
          final fullNameController = state.textController('fullName', text: user.fullName);
          final pinController = state.textController('pin');
          final selectedRole = state.value<UserRole>('role', user.role);

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: AppAvatar(
                    imagePath: user.profileImagePath,
                    initials: user.fullName,
                    radius: 40,
                    backgroundColor: _roleColor(
                      user.role,
                      Theme.of(context).colorScheme,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                AppTextFormField(
                  controller: usernameController,
                  label: 'Username',
                  prefixIcon: Icons.person_outline,
                  validator: (value) =>
                      Validators.required(value, 'Username'),
                  onChanged: (_) => state.markChanged(),
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: fullNameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person,
                  validator: (value) =>
                      Validators.required(value, 'Full Name'),
                  onChanged: (_) => state.markChanged(),
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: pinController,
                  label: 'PIN (optional)',
                  prefixIcon: Icons.lock_outline,
                  hint: user.hasPin
                      ? 'Enter new PIN to replace (${user.configuredPinLength} digits)'
                      : '4-6 digits',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return Validators.pin(value);
                  },
                  onChanged: (_) => state.markChanged(),
                ),
                const SizedBox(height: 12),
                AppDropdownField<int>(
                  label: 'Inactivity timeout',
                  hint: 'Use store default',
                  prefixIcon: Icons.timer_outlined,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Use store default')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('60 minutes')),
                  ],
                  initialValue: state.value<int>('inactivityTimeout', user.inactivityTimeoutMinutes),
                  onChanged: (value) {
                    state.setValue<int>('inactivityTimeout', value);
                  },
                ),
                const SizedBox(height: 12),
                AppDropdownField<UserRole>(
                  label: 'Role',
                  prefixIcon: Icons.badge_outlined,
                  items: roleItems
                      .map((role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.displayName),
                          ))
                        .toList(),
                  initialValue: selectedRole,
                  onChanged: (value) {
                    if (value != null) {
                      state.setValue<UserRole>('role', value);
                    }
                  },
                ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (dialogContext) => _confirmCancelEdit(state, dialogContext),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (dialogContext) => _saveUser(state, user, dialogContext),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result case final r?) {
      if (r.isSaved) {
        await AppDialogService.success(
          context,
          title: 'Updated',
          message: 'User updated successfully.',
        );
        await _refresh();
      }
    }
  }

  Future<void> _confirmCancelEdit(
    AppDialogFormState<ModalResult<void>> state,
    BuildContext dialogContext,
  ) async {
    if (state.isSaving) return;
    if (state.hasChanges) {
      final discard = await AppDialogService.unsavedChanges(dialogContext);
      if (discard == true && dialogContext.mounted) {
        state.pop(const ModalResult<void>.cancelled());
      }
    } else if (dialogContext.mounted) {
      state.pop(const ModalResult<void>.cancelled());
    }
  }

  Future<void> _saveUser(
    AppDialogFormState<ModalResult<void>> state,
    User user,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) return;

    state.setSaving(true);

    final pinValue = state.textController('pin').text.trim();
    final result = await ref.read(userControllerProvider.notifier).updateUser(
          userId: user.id!,
          username: state.textController('username').text.trim(),
          fullName: state.textController('fullName').text.trim(),
          role: state.value<UserRole>('role')!,
          pin: pinValue.isEmpty ? null : pinValue,
          inactivityTimeoutMinutes: state.value<int>('inactivityTimeout'),
        );

    if (result.success) {
      state.pop(const ModalResult<void>.saved());
    } else {
      if (dialogContext.mounted) {
        state.setSaving(false);
        await AppDialogService.error(
          dialogContext,
          title: 'Update Failed',
          message: result.message,
        );
      }
    }
  }

  // ── ADD USER ─────────────────────────────────────────────────────────

  Future<void> _showAddUserDialog() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_users')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final currentUser = ref.read(authStateProvider).user;
    final manageableRoles =
        UserRoleManagement.manageableBy(currentUser?.role ?? UserRole.staff);

    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.add,
        title: 'Add User',
        childBuilder: (context, state) {
          final usernameController = state.textController('username');
          final fullNameController = state.textController('fullName');
          final pinController = state.textController('pin');
          final selectedRole = state.value<UserRole>('role', UserRole.staff);

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Temp password info card ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
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
                            'A temporary password will be assigned. The user must change it on first login.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextFormField(
                    controller: usernameController,
                    label: 'Username',
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        Validators.required(value, 'Username'),
                    onChanged: (_) => state.markChanged(),
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: fullNameController,
                    label: 'Full Name',
                    prefixIcon: Icons.person,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        Validators.required(value, 'Full Name'),
                    onChanged: (_) => state.markChanged(),
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: pinController,
                    label: 'PIN (optional)',
                    hint: '4-6 digits',
                    prefixIcon: Icons.lock_outline,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
                    },
                    onChanged: (_) => state.markChanged(),
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  AppDropdownField<int>(
                    label: 'Inactivity timeout',
                    hint: 'Use store default',
                    prefixIcon: Icons.timer_outlined,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Use store default')),
                      DropdownMenuItem(value: 5, child: Text('5 minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('60 minutes')),
                    ],
                    initialValue: state.value<int>('inactivityTimeout'),
                    onChanged: (value) {
                      state.setValue<int>('inactivityTimeout', value);
                    },
                  ),
                  const SizedBox(height: 12),
                  AppDropdownField<UserRole>(
                    label: 'Role',
                    prefixIcon: Icons.badge_outlined,
                    items: manageableRoles
                        .map((role) => DropdownMenuItem(
                              value: role,
                              child: Text(role.displayName),
                            ))
                        .toList(),
                    initialValue: selectedRole,
                    onChanged: (value) {
                      if (value != null) {
                        state.setValue<UserRole>('role', value);
                      }
                    },
                    validator: (value) {
                      if (value == null) return 'Role is required';
                      return null;
                    },
                  ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (dialogContext) => state.pop(const ModalResult<void>.cancelled()),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (dialogContext) => _saveNewUser(state, dialogContext),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result case final r?) {
      if (r.isSaved) {
        await AppDialogService.success(
          context,
          title: 'User Created',
          message:
              'User created successfully. The temporary password is ${AppConstants.defaultTemporaryPassword}.',
        );
        await _refresh();
      }
    }
  }

  Future<void> _saveNewUser(
    AppDialogFormState<ModalResult<void>> state,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) return;

    state.setSaving(true);

    final pinValue = state.textController('pin').text.trim();
    final result = await ref.read(userControllerProvider.notifier).createUser(
          username: state.textController('username').text.trim(),
          fullName: state.textController('fullName').text.trim(),
          role: state.value<UserRole>('role')!,
          pin: pinValue.isEmpty ? null : pinValue,
          inactivityTimeoutMinutes: state.value<int>('inactivityTimeout'),
        );

    if (result.success) {
      state.pop(const ModalResult<void>.saved());
    } else {
      if (dialogContext.mounted) {
        state.setSaving(false);
        await AppDialogService.error(
          dialogContext,
          title: 'Create Failed',
          message: result.message,
        );
      }
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userControllerProvider);
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManage = authNotifier.hasPermission('manage_users');
    final canEdit = authNotifier.hasPermission('edit_users');
    final canDelete = authNotifier.hasPermission('delete_users');
    final canResetPassword = authNotifier.hasPermission('reset_password');
    final canToggleActive = authNotifier.hasPermission('toggle_user_active');
    final currentUser = ref.read(authStateProvider).user;
    final colorScheme = Theme.of(context).colorScheme;

    final createAction = canManage
        ? ResponsiveCreateAction(
            label: 'Add User',
            icon: Icons.person_add,
            onPressed: _showAddUserDialog,
          )
        : null;

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;
    final showSearch =
        userState.users.isNotEmpty || _searchQuery.isNotEmpty;

    return Scaffold(
      appBar: const AppHeader(
        title: 'Users',
        showBackButton: true,
      ),
      floatingActionButton: createFab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Content toolbar: search + refresh + primary add action ──
          if (showSearch || toolbarAction != null)
            CrudToolbar(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              search: showSearch
                  ? AppSearchField(
                      controller: _searchController,
                      hint: 'Search by name or username',
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              pinnedControls: [
                AppIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                ),
              ],
              primaryAction: toolbarAction,
            ),
          // ── Role filter chips ──
          if (userState.users.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.xs,
              ),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _roleFilter == null,
                      onSelected: () =>
                          setState(() => _roleFilter = null),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: UserRole.owner.displayName,
                      selected: _roleFilter == UserRole.owner,
                      onSelected: () =>
                          setState(() => _roleFilter = UserRole.owner),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: UserRole.admin.displayName,
                      selected: _roleFilter == UserRole.admin,
                      onSelected: () =>
                          setState(() => _roleFilter = UserRole.admin),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: UserRole.staff.displayName,
                      selected: _roleFilter == UserRole.staff,
                      onSelected: () =>
                          setState(() => _roleFilter = UserRole.staff),
                    ),
                  ],
                ),
              ),
            ),
          // ── User list ──
          Expanded(
            child: _buildBody(
              userState,
              canEdit,
              canDelete,
              canResetPassword,
              canToggleActive,
              currentUser,
              colorScheme,
              bottomClearance,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    UserListState userState,
    bool canEdit,
    bool canDelete,
    bool canResetPassword,
    bool canToggleActive,
    User? currentUser,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    if (userState.isLoading) {
      return const LoadingState();
    }

    if (userState.error != null && userState.users.isEmpty) {
      return ErrorState(
        title: 'Failed to Load Users',
        message: userState.error,
        onRetry: _refresh,
      );
    }

    if (userState.users.isEmpty) {
      return EmptyState(
        icon: Icons.people,
        title: 'No Users Yet',
        message: 'Create a user account to get started.',
      );
    }

    final filteredUsers = _filterUsers(userState.users);

    if (filteredUsers.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No Results',
        message: 'No users match your search.',
      );
    }

    return _buildUserList(
      filteredUsers,
      currentUser,
      colorScheme,
      canEdit,
      canDelete,
      canResetPassword,
      canToggleActive,
      bottomClearance,
    );
  }

  Widget _buildUserList(
    List<User> filteredUsers,
    User? currentUser,
    ColorScheme colorScheme,
    bool canEdit,
    bool canDelete,
    bool canResetPassword,
    bool canToggleActive,
    double bottomClearance,
  ) {
    final count = filteredUsers.length;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xs,
        Spacing.lg,
        Spacing.lg + bottomClearance,
      ),
      itemCount: count + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(
              left: Spacing.sm,
              top: Spacing.sm,
              bottom: Spacing.md,
            ),
            child: Text(
              '$count user${count == 1 ? '' : 's'}',
              style: AppTypography.labelMedium(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }

        final user = filteredUsers[index - 1];
        final isSelf = currentUser?.id == user.id;
        final roleColor = _roleColor(user.role, colorScheme);

        final chips = <Widget>[
          if (!user.isActive)
            _StatusBadge(
              label: 'Inactive',
              color: colorScheme.error,
              icon: Icons.pause_circle,
            ),
          if (user.mustChangePassword)
            _StatusBadge(
              label: 'Temp Password',
              color: AppSemanticColors.resolve(
                AppSemanticColors.warning,
                Theme.of(context).brightness,
              ),
              icon: Icons.key,
            ),
          if (user.hasPin)
            _StatusBadge(
              label: 'PIN',
              color: AppSemanticColors.resolve(
                AppSemanticColors.info,
                Theme.of(context).brightness,
              ),
              icon: Icons.lock,
            ),
        ];

        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: AppListItem(
            leading: AppAvatar(
              imagePath: user.profileImagePath,
              initials: user.fullName,
              radius: 24,
              backgroundColor: roleColor,
            ),
            title: user.fullName,
            subtitle: '@${user.username}',
            trailing: _RoleBadge(role: user.role, color: roleColor),
            chips: chips,
            onTap: (canEdit || canDelete) && !isSelf
                ? () => _showUserActionsSheet(
                      user,
                      canEdit,
                      canDelete,
                      canResetPassword,
                      canToggleActive,
                      isSelf,
                    )
                : null,
          ),
        );
      },
    );
  }

  void _showUserActionsSheet(
    User user,
    bool canEdit,
    bool canDelete,
    bool canResetPassword,
    bool canToggleActive,
    bool isSelf,
  ) {
    final roleColor = _roleColor(user.role, Theme.of(context).colorScheme);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AppAvatar(
                imagePath: user.profileImagePath,
                initials: user.fullName,
                radius: 24,
                backgroundColor: roleColor,
              ),
              title: Text(user.fullName),
              subtitle: Text('@${user.username}'),
            ),
            const Divider(),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit User'),
                onTap: () {
                  Navigator.pop(context);
                  _editUser(user);
                },
              ),
            if (canResetPassword)
              ListTile(
                leading: const Icon(Icons.lock_reset),
                title: const Text('Reset Password'),
                onTap: () {
                  Navigator.pop(context);
                  _resetPassword(user);
                },
              ),
            if (canToggleActive && !isSelf)
              ListTile(
                leading: Icon(user.isActive
                    ? Icons.person_off
                    : Icons.person),
                title: Text(user.isActive ? 'Deactivate' : 'Activate'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleUserActive(user);
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Delete',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteUser(user);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final UserRole role;
  final Color color;

  const _RoleBadge({required this.role, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role.displayName,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
