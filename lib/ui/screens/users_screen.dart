import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
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
    return switch (role) {
      UserRole.owner => colorScheme.tertiary,
      UserRole.admin => colorScheme.primary,
      UserRole.staff => colorScheme.secondary,
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will reset the password for ${user.fullName} (@${user.username}) to the default temporary password.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppSemanticColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The user will be required to change it on next login.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
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

    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: user.username);
    final fullNameController = TextEditingController(text: user.fullName);
    final pinController = TextEditingController();
    UserRole selectedRole = user.role;
    bool hasChanges = false;
    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit User: ${user.username}'),
          content: SingleChildScrollView(
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
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => Validators.required(value, 'Full Name'),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pinController,
                    decoration: InputDecoration(
                      labelText: 'PIN (optional)',
                      border: const OutlineInputBorder(),
                      hintText: user.hasPin
                          ? 'Enter new PIN to replace (${user.configuredPinLength} digits)'
                          : '4-6 digits',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
                    },
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: UserRole.owner, child: Text('Owner')),
                      DropdownMenuItem(
                          value: UserRole.admin, child: Text('System Admin')),
                      DropdownMenuItem(
                          value: UserRole.staff, child: Text('Staff')),
                    ],
                    initialValue: selectedRole,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedRole = value;
                          hasChanges = true;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (hasChanges) {
                  final discard = await AppDialogService.unsavedChanges(context);
                  if (discard == true && context.mounted) {
                    Navigator.pop(context, false);
                  }
                } else {
                  Navigator.pop(context, false);
                }
              },
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final pinValue = pinController.text.trim();
                final res = await ref
                    .read(userControllerProvider.notifier)
                    .updateUser(
                  userId: user.id!,
                  username: usernameController.text.trim(),
                  fullName: fullNameController.text.trim(),
                  role: selectedRole,
                  pin: pinValue.isEmpty ? null : pinValue,
                );
                if (context.mounted) {
                  setState(() => isSaving = false);
                  Navigator.pop(context, res.success);
                }
              },
              label: 'Save',
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      await AppDialogService.success(context, title: 'Updated', message: 'User updated successfully.');
    } else if (result == false && mounted) {
      AppDialogService.error(context, title: 'Update Failed', message: ref.read(userControllerProvider).error ?? 'Failed to update user');
    }
  }

  // ── ADD USER ─────────────────────────────────────────────────────────

  void _showAddUserDialog() {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_users')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final pinController = TextEditingController();
    UserRole? selectedRole = UserRole.staff;
    bool hasChanges = false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add User'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
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
                            'A temporary password will be assigned. The user must change it on first login.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        Validators.required(value, 'Username'),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        Validators.required(value, 'Full Name'),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pinController,
                    decoration: const InputDecoration(
                      labelText: 'PIN (optional)',
                      border: OutlineInputBorder(),
                      hintText: '4-6 digits',
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
                    },
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: UserRole.owner, child: Text('Owner')),
                      DropdownMenuItem(
                          value: UserRole.admin, child: Text('System Admin')),
                      DropdownMenuItem(
                          value: UserRole.staff, child: Text('Staff')),
                    ],
                    initialValue: selectedRole,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedRole = value;
                          hasChanges = true;
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null) return 'Role is required';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (hasChanges) {
                  final discard =
                      await AppDialogService.unsavedChanges(context);
                  if (discard == true && context.mounted) {
                    Navigator.pop(context);
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final pinValue = pinController.text.trim();
                final res = await ref
                    .read(userControllerProvider.notifier)
                    .createUser(
                  username: usernameController.text.trim(),
                  fullName: fullNameController.text.trim(),
                  role: selectedRole ?? UserRole.staff,
                  pin: pinValue.isEmpty ? null : pinValue,
                );
                if (context.mounted) {
                  setState(() => isSaving = false);
                }
                if (res.success) {
                  if (context.mounted) {
                    await AppDialogService.success(
                      context,
                      title: 'User Created',
                      message: '${res.message} The temporary password is ${AppConstants.defaultTemporaryPassword}.',
                    );
                  }
                  if (context.mounted) Navigator.pop(context);
                } else {
                  if (context.mounted) {
                    AppDialogService.error(
                      context,
                      title: 'Create Failed',
                      message: res.message,
                    );
                  }
                }
              },
              label: 'Save',
            ),
          ],
        ),
      ),
    );
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget? createAction = canManage
        ? (isTablet
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AppButton.filled(
                  size: AppButtonSize.small,
                  icon: Icons.person_add,
                  label: 'Add User',
                  onPressed: () => _showAddUserDialog(),
                ),
              )
            : null)
        : null;

    return Scaffold(
      appBar: AppHeader(
        title: 'Users',
        actions: [
          ?createAction,
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: canManage && !isTablet
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Add User'),
              onPressed: () => _showAddUserDialog(),
            )
          : null,
      body: Column(
        children: [
          // ── Search bar ──
          if (userState.users.isNotEmpty || _searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or username...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          // ── Role filter chips ──
          if (userState.users.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              canManage,
              canEdit,
              canDelete,
              canResetPassword,
              canToggleActive,
              currentUser,
              theme,
              colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    UserListState userState,
    bool canManage,
    bool canEdit,
    bool canDelete,
    bool canResetPassword,
    bool canToggleActive,
    User? currentUser,
    ThemeData theme,
    ColorScheme colorScheme,
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
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        final isSelf = currentUser?.id == user.id;
        final roleColor = _roleColor(user.role, colorScheme);

        final chips = <Widget>[
          _RoleBadge(role: user.role, color: roleColor),
          if (!user.isActive)
            _StatusBadge(
              label: 'Inactive',
              color: colorScheme.error,
              icon: Icons.pause_circle,
            ),
          if (user.mustChangePassword)
            _StatusBadge(
              label: 'Temp Password',
              color: colorScheme.tertiary,
              icon: Icons.key,
            ),
          if (user.hasPin)
            _StatusBadge(
              label: 'PIN',
              color: colorScheme.secondary,
              icon: Icons.lock,
            ),
        ];

        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: AppListItem(
            leading: AppAvatar(
              imagePath: user.profileImagePath,
              initials: user.fullName.isNotEmpty
                  ? user.fullName[0].toUpperCase()
                  : '?',
              radius: 24,
            ),
            title: user.fullName,
            subtitle: '@${user.username}',
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
            trailing: (canEdit || canDelete) && !isSelf
                ? _UserActionsMenu(
                    user: user,
                    canEdit: canEdit,
                    canDelete: canDelete,
                    canResetPassword: canResetPassword,
                    canToggleActive: canToggleActive,
                    isSelf: isSelf,
                    onEdit: _editUser,
                    onResetPassword: _resetPassword,
                    onToggleActive: _toggleUserActive,
                    onDelete: _deleteUser,
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
                initials: user.fullName.isNotEmpty
                    ? user.fullName[0].toUpperCase()
                    : '?',
                radius: 24,
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

class _UserActionsMenu extends StatelessWidget {
  final User user;
  final bool canEdit;
  final bool canDelete;
  final bool canResetPassword;
  final bool canToggleActive;
  final bool isSelf;
  final void Function(User) onEdit;
  final void Function(User) onResetPassword;
  final void Function(User) onToggleActive;
  final void Function(User) onDelete;

  const _UserActionsMenu({
    required this.user,
    required this.canEdit,
    required this.canDelete,
    required this.canResetPassword,
    required this.canToggleActive,
    required this.isSelf,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (action) {
        switch (action) {
          case 'edit':
            onEdit(user);
          case 'reset_password':
            onResetPassword(user);
          case 'toggle_active':
            onToggleActive(user);
          case 'delete':
            onDelete(user);
        }
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('Edit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canResetPassword)
          const PopupMenuItem(
            value: 'reset_password',
            child: ListTile(
              leading: Icon(Icons.lock_reset),
              title: Text('Reset Password'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canToggleActive && !isSelf)
          PopupMenuItem(
            value: 'toggle_active',
            child: ListTile(
              leading: Icon(user.isActive ? Icons.person_off : Icons.person),
              title: Text(user.isActive ? 'Deactivate' : 'Activate'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete),
              title: Text('Delete'),
              contentPadding: EdgeInsets.zero,
            ),
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
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        role.displayName,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
