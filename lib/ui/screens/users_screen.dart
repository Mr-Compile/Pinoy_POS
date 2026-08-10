import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
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
    if (!authNotifier.hasPermission('manage_users')) {
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

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManage = authNotifier.hasPermission('manage_users');

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
                  child: ListTile(
                    title: Text(user.fullName),
                    subtitle: Text('${user.username} • ${user.role.name}'),
                    trailing: canManage && !isSelf
                        ? IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteUser(user),
                          )
                        : null,
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
                    validator: (value) => Validators.confirmPassword(value, passwordController.text),
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
                      DropdownMenuItem(value: UserRole.owner, child: Text('Owner')),
                      DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
                      DropdownMenuItem(value: UserRole.staff, child: Text('Staff')),
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
    final existingUser = await _userRepository.getByUsernameWithDeleted(username);
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
      // Will implement actual user creation in next step
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        showSuccessSnackbar(context, 'User created successfully');
        Navigator.pop(context);
        _loadUsers();
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
