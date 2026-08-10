import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/confirm_dialog.dart';

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
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete User',
      message: 'Are you sure you want to delete ${user.username}?',
    );

    if (confirmed == true) {
      await _userRepository.softDelete(user.id!);
      _loadUsers();
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
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(user.fullName),
                    subtitle: Text('${user.username} • ${user.role.name}'),
                    trailing: canManage
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
    // User creation dialog to be implemented
  }
}
