import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  @override
  void initState() {
    super.initState();
    // Load users from SQLite via the controller on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userControllerProvider.notifier).loadUsers();
    });
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text(
          '${user.fullName} (@${user.username}) will be moved to Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Deactivate User?'),
          content: Text(
            '${user.fullName} will no longer be able to log in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Deactivate'),
            ),
          ],
        ),
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

    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Reset Password for ${user.username}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autofocus: true,
                    validator: (value) => Validators.password(value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) =>
                        Validators.confirmPassword(value, passwordController.text),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final res = await ref
                    .read(userControllerProvider.notifier)
                    .resetPassword(
                  userId: user.id!,
                  newPassword: passwordController.text,
                );
                if (context.mounted) {
                  Navigator.pop(context, res.success);
                }
              },
              label: 'Reset',
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      await AppDialogService.success(context, title: 'Password Reset', message: 'Password reset successfully.');
    } else if (result == false && mounted) {
      AppDialogService.error(context, title: 'Reset Failed', message: 'Failed to reset password.');
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
    final pinController = TextEditingController(text: user.pin ?? '');
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
                    decoration: const InputDecoration(
                      labelText: 'PIN (optional)',
                      border: OutlineInputBorder(),
                      hintText: '4-6 digits',
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
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
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
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.required(value, 'Username'),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.required(value, 'Full Name'),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.password(value),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.confirmPassword(
                        value, passwordController.text),
                    onChanged: (_) {
                      if (!hasChanges) setState(() => hasChanges = true);
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                  final discard = await AppDialogService.unsavedChanges(context);
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
                  password: passwordController.text,
                  fullName: fullNameController.text.trim(),
                  role: selectedRole ?? UserRole.staff,
                  pin: pinValue.isEmpty ? null : pinValue,
                );
                if (context.mounted) {
                  setState(() => isSaving = false);
                }
                if (res.success) {
                  if (context.mounted) {
                    await AppDialogService.success(context, title: 'Created', message: res.message);
                  }
                  if (context.mounted) Navigator.pop(context);
                } else {
                  if (context.mounted) {
                    AppDialogService.error(context, title: 'Create Failed', message: res.message);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add User',
              onPressed: () => _showAddUserDialog(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(
        userState,
        canEdit,
        canDelete,
        canResetPassword,
        canToggleActive,
        currentUser,
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
      return const EmptyState(
        icon: Icons.people,
        title: 'No Users',
        message: 'Add users to manage access',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: userState.users.length,
      itemBuilder: (context, index) {
        final user = userState.users[index];
        final isSelf = currentUser?.id == user.id;

        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(user.fullName),
                subtitle: Text(
                  '${user.username} • ${user.role.displayName}'
                  '${user.isActive ? '' : ' (Inactive)'}',
                ),
                trailing: (canEdit || canDelete) && !isSelf
                    ? PopupMenuButton<String>(
                        tooltip: 'Actions',
                        onSelected: (action) {
                          switch (action) {
                            case 'edit':
                              _editUser(user);
                              break;
                            case 'reset_password':
                              _resetPassword(user);
                              break;
                            case 'toggle_active':
                              _toggleUserActive(user);
                              break;
                            case 'delete':
                              _deleteUser(user);
                              break;
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
                                leading: Icon(user.isActive
                                    ? Icons.person_off
                                    : Icons.person),
                                title: Text(user.isActive
                                    ? 'Deactivate'
                                    : 'Activate'),
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
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
