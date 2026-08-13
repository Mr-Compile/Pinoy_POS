import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final UserRepository _userRepository = UserRepository();
  final AuthService _authService = AuthService();
  List<User> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    final users = await _userRepository.getAllActive();

    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_users')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    // Prevent deleting self
    final currentUser = ref.read(authStateProvider).user;
    if (currentUser?.id == user.id) {
      showErrorSnackbar(context, 'You cannot delete your own account');
      return;
    }

    final confirmed = await EnhancedDialogs.showDeleteDialog(
      context: context,
      itemName: user.username,
    );

    if (confirmed == true && mounted) {
      try {
        await _userRepository.softDelete(user.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'User deleted successfully');
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to delete user');
        }
      }
    }
  }

  Future<void> _toggleUserActive(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('toggle_user_active')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final currentUser = ref.read(authStateProvider).user;
    if (currentUser?.id == user.id) {
      showErrorSnackbar(context, 'You cannot deactivate your own account');
      return;
    }

    try {
      final success = await _authService.toggleUserActive(user.id!, !user.isActive);
      if (mounted) {
        if (success) {
          showSuccessSnackbar(
              context, user.isActive ? 'User deactivated' : 'User activated');
          _loadUsers();
        } else {
          showErrorSnackbar(context, 'Failed to update user status');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to update user status');
      }
    }
  }

  Future<void> _resetPassword(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('reset_password')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
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
                try {
                  final success = await _authService.resetPassword(
                    user.id!,
                    passwordController.text,
                  );
                  if (context.mounted) {
                    Navigator.pop(context, success);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context, false);
                  }
                }
              },
              label: 'Reset',
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      showSuccessSnackbar(context, 'Password reset successfully');
    } else if (result == false && mounted) {
      showErrorSnackbar(context, 'Failed to reset password');
    }
  }

  Future<void> _editUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('edit_users')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(text: user.fullName);
    UserRole selectedRole = user.role;
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
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    validator: (value) => Validators.required(value, 'Full Name'),
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
                        setState(() => selectedRole = value);
                      }
                    },
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
                try {
                  final success = await _authService.updateUser(
                    userId: user.id!,
                    fullName: fullNameController.text.trim(),
                    role: selectedRole,
                  );
                  if (context.mounted) {
                    Navigator.pop(context, success);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context, false);
                  }
                }
              },
              label: 'Save',
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      showSuccessSnackbar(context, 'User updated successfully');
      _loadUsers();
    } else if (result == false && mounted) {
      showErrorSnackbar(context, 'Failed to update user');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManage = authNotifier.hasPermission('manage_users');
    final canEdit = authNotifier.hasPermission('edit_users');
    final canDelete = authNotifier.hasPermission('delete_users');
    final canResetPassword = authNotifier.hasPermission('reset_password');
    final canToggleActive = authNotifier.hasPermission('toggle_user_active');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Users'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add User',
              onPressed: () => _showUserDialog(),
            ),
        ],
      ),
      body: _users.isEmpty
          ? const EmptyState(
              icon: Icons.people,
              title: 'No Users',
              message: 'Add users to manage access',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final currentUser = ref.read(authStateProvider).user;
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
                          '${user.username} • ${user.role.displayName}${user.isActive ? '' : ' (Inactive)'}',
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
            ),
    );
  }

  void _showUserDialog() {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
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
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
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
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
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
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
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
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
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
                      setState(() {
                        selectedRole = value;
                        hasChanges = true;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Role is required';
                      }
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
                  final discard = await EnhancedDialogs.showUnsavedChangesDialog(
                    context: context,
                  );
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
              onPressed: () => _saveUser(
                formKey,
                usernameController,
                fullNameController,
                passwordController,
                confirmPasswordController,
                selectedRole,
                setState,
                isSaving,
              ),
              label: 'Save',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveUser(
    GlobalKey<FormState> formKey,
    TextEditingController usernameController,
    TextEditingController fullNameController,
    TextEditingController passwordController,
    TextEditingController confirmPasswordController,
    UserRole? selectedRole,
    StateSetter setState,
    bool isSaving,
  ) async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final username = usernameController.text.trim();

    // Check for duplicate username
    final existingUser =
        await _userRepository.getByUsernameWithDeleted(username);
    if (existingUser != null) {
      if (mounted) {
        showErrorSnackbar(context, 'Username already exists');
      }
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final success = await _authService.createUser(
        username: username,
        password: passwordController.text,
        fullName: fullNameController.text.trim(),
        role: selectedRole ?? UserRole.staff,
      );

      if (mounted) {
        if (success) {
          showSuccessSnackbar(context, 'User created successfully');
          Navigator.pop(context);
          _loadUsers();
        } else {
          showErrorSnackbar(context,
              'Failed to create user (username may already exist or password too short)');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to create user');
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }
}
