import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    child: Text(
                      user.fullName.isNotEmpty
                          ? user.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 36),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.fullName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(user.role.displayName),
                    avatar: const Icon(Icons.badge),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Account Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Full Name'),
                    subtitle: Text(user.fullName),
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () => _showEditProfileDialog(user),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: const Text('Username'),
                    subtitle: Text(user.username),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings),
                    title: const Text('Role'),
                    subtitle: Text(user.role.displayName),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Member Since'),
                    subtitle: Text(user.createdAt.toLocal().toString().split('.')[0]),
                  ),
                  if (user.lastLogin != null) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.login),
                      title: const Text('Last Login'),
                      subtitle: Text(user.lastLogin!.toLocal().toString().split('.')[0]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Preferences',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Accent Color'),
                subtitle: Text(user.colorPreference.toUpperCase()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showColorPreferenceDialog(user),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Security',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showChangePasswordDialog(user),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.pin),
                    title: const Text('PIN'),
                    subtitle: Text(user.pin != null ? 'Set (${user.pin!.length} digits)' : 'Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showEditPinDialog(user),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── EDIT PROFILE (full name) ─────────────────────────────────────────

  void _showEditProfileDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(text: user.fullName);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Profile'),
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final success = await ref
                    .read(authStateProvider.notifier)
                    .updateProfile(
                      userId: user.id!,
                      fullName: fullNameController.text.trim(),
                    );
                if (context.mounted) {
                  setState(() => isSaving = false);
                  Navigator.pop(context);
                  if (success) {
                    showSuccessSnackbar(context, 'Profile updated successfully');
                  } else {
                    showErrorSnackbar(context, 'Failed to update profile');
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

  // ── EDIT PIN ─────────────────────────────────────────────────────────

  void _showEditPinDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final pinController = TextEditingController(text: user.pin ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set PIN'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: pinController,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4-6 digits)',
                      border: OutlineInputBorder(),
                      hintText: 'Leave empty to clear',
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Validators.pin(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final pinValue = pinController.text.trim();
                final success = await ref
                    .read(authStateProvider.notifier)
                    .updateProfile(
                      userId: user.id!,
                      fullName: user.fullName,
                      pin: pinValue.isEmpty ? null : pinValue,
                    );
                if (context.mounted) {
                  setState(() => isSaving = false);
                  Navigator.pop(context);
                  if (success) {
                    showSuccessSnackbar(context, 'PIN updated successfully');
                  } else {
                    showErrorSnackbar(context, 'Failed to update PIN');
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

  // ── COLOR PREFERENCE ─────────────────────────────────────────────────

  void _showColorPreferenceDialog(User user) {
    final colors = AppColors.accentColors.keys.toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accent Color'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: colors.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final color = colors[index];
              final isSelected = color == user.colorPreference;
              return _ColorOption(
                name: color,
                color: AppColors.getAccentColor(color),
                isSelected: isSelected,
                onTap: () async {
                  final success = await ref
                      .read(authStateProvider.notifier)
                      .updateProfile(
                        userId: user.id!,
                        fullName: user.fullName,
                        colorPreference: color,
                      );
                  if (context.mounted) {
                    Navigator.pop(context);
                    if (success) {
                      showSuccessSnackbar(context, 'Accent color updated');
                    } else {
                      showErrorSnackbar(context, 'Failed to update accent color');
                    }
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ── CHANGE PASSWORD ──────────────────────────────────────────────────

  void _showChangePasswordDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: oldPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autofocus: true,
                    validator: (value) => Validators.required(value, 'Current password'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: newPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) => Validators.password(value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) =>
                        Validators.confirmPassword(value, newPasswordController.text),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => isSaving = true);
                final result = await ref
                    .read(userControllerProvider.notifier)
                    .changePassword(
                      userId: user.id!,
                      oldPassword: oldPasswordController.text,
                      newPassword: newPasswordController.text,
                    );
                if (context.mounted) {
                  setState(() => isSaving = false);
                  Navigator.pop(context);
                  if (result.success) {
                    showSuccessSnackbar(context, result.message);
                  } else {
                    showErrorSnackbar(context, result.message);
                  }
                }
              },
              label: 'Change',
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  final String name;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.name,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${name[0].toUpperCase()}${name.substring(1)} accent',
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name[0].toUpperCase() + name.substring(1),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
