import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Profile screen — shows the current user's profile information and
/// allows editing their full name and profile picture.
///
/// Security (password) and PIN management have been moved to the
/// Settings hub sub-pages ([SecuritySettingsPage] and
/// [PinSettingsPage]).
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
        appBar: const AppHeader(title: 'Profile', showBackButton: true),
        body: const Center(child: Text('No user logged in')),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Profile', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name header
            Center(
              child: Column(
                children: [
                  _buildAvatar(user),
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
            // Account information
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
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () => _showEditProfileDialog(user),
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
                    subtitle:
                        Text(user.createdAt.toLocal().toString().split('.')[0]),
                  ),
                  if (user.lastLogin != null) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.login),
                      title: const Text('Last Login'),
                      subtitle: Text(
                          user.lastLogin!.toLocal().toString().split('.')[0]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AVATAR ───────────────────────────────────────────────────────────

  Widget _buildAvatar(User user) {
    return Stack(
      children: [
        AppAvatar(
          imagePath: user.profileImagePath,
          initials: user.fullName,
          radius: 48,
          semanticLabel: 'Profile picture',
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: Theme.of(context).colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => _changeProfilePicture(user),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── CHANGE PROFILE PICTURE ───────────────────────────────────────────

  Future<void> _changeProfilePicture(User user) async {
    final imageService = ImageService();
    final result = await imageService.pickAndStoreImage();

    if (!mounted) return;

    if (!result.isSuccess) {
      if (result.error != 'No image selected') {
        await AppDialogService.error(
          context,
          title: 'Image Error',
          message: result.error ?? 'Failed to select image.',
        );
      }
      return;
    }

    final oldImagePath = user.profileImagePath;

    final success = await ref.read(authStateProvider.notifier).updateProfile(
          userId: user.id!,
          fullName: user.fullName,
          profileImagePath: result.filePath,
        );

    if (!mounted) return;

    if (success) {
      if (oldImagePath != null && oldImagePath.isNotEmpty) {
        await imageService.deleteImage(oldImagePath);
      }
      if (!mounted) return;
      await AppDialogService.success(
        context,
        title: 'Profile Picture Updated',
        message: 'Your profile picture has been saved.',
      );
    } else {
      await AppDialogService.error(
        context,
        title: 'Update Failed',
        message: 'Failed to update profile picture. Please try again.',
      );
    }
  }

  // ── EDIT PROFILE (full name) ─────────────────────────────────────────

  void _showEditProfileDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(text: user.fullName);
    final usernameController = TextEditingController(text: user.username);
    bool isSaving = false;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          type: AppDialogType.info,
          title: 'Edit Profile',
          actions: [
            AppDialogAction(
              label: 'Cancel',
              onPressed: (context) =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
            AppDialogAction(
              label: 'Save',
              isPrimary: true,
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : (context) async {
                      if (!formKey.currentState!.validate()) return;

                      final newUsername = usernameController.text.trim();
                      final isChangingUsername =
                          newUsername != user.username;

                      if (isChangingUsername && !user.hasChangedUsername) {
                        final confirmed = await AppDialogService.confirmation(
                          context,
                          title: 'Change Username?',
                          message:
                              'You can only change your username once. After saving, it will be permanently set to "$newUsername".',
                          confirmLabel: 'Yes, Change It',
                          cancelLabel: 'Cancel',
                        );
                        if (confirmed != true) return;
                      }

                      if (!context.mounted) return;
                      setState(() => isSaving = true);
                      final success = await ref
                          .read(authStateProvider.notifier)
                          .updateProfile(
                            userId: user.id!,
                            fullName: fullNameController.text.trim(),
                            username: newUsername,
                          );
                      if (context.mounted) {
                        setState(() => isSaving = false);
                        if (success) {
                          await AppDialogService.success(
                            context,
                            title: 'Profile Updated',
                            message: isChangingUsername
                                ? 'Your profile and username have been updated.'
                                : 'Profile updated successfully.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
                        } else {
                          await AppDialogService.error(
                            context,
                            title: 'Update Failed',
                            message: isChangingUsername
                                ? 'Failed to change username. It may already be in use or you may have already changed it.'
                                : 'Failed to update profile.',
                          );
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pop();
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
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    validator: (value) =>
                        Validators.required(value, 'Full Name'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: usernameController,
                    readOnly: user.hasChangedUsername,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      border: const OutlineInputBorder(),
                      helperText: user.hasChangedUsername
                          ? 'You have already changed your username.'
                          : 'You can only change your username once.',
                    ),
                    validator: (value) => Validators.compose([
                      (v) => Validators.required(v, 'Username'),
                      (v) => Validators.minLength(v, 3, 'Username'),
                      (v) => Validators.maxLength(v, 50, 'Username'),
                    ], value),
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
