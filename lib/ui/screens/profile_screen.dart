import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Profile screen — shows the current user’s profile information and
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (user == null) {
      return Scaffold(
        appBar: const AppHeader(title: 'Profile', showBackButton: true),
        body: const Center(child: Text('No user logged in')),
      );
    }

    final brightness = theme.brightness;
    final successColor = AppSemanticColors.resolve(
      AppSemanticColors.success,
      brightness,
    );

    return Scaffold(
      appBar: const AppHeader(title: 'Profile', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar + name header
            Center(
              child: Column(
                children: [
                  _buildAvatar(user),
                  const SizedBox(height: 16),
                  Text(
                    user.fullName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _RolePill(
                    role: user.role.displayName,
                    color: successColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppButton.gradient(
              label: 'Edit Profile',
              fullWidth: true,
              onPressed: () => _showEditProfileDialog(user),
            ),
            const SizedBox(height: 24),
            // Account information
            _SectionLabel(label: 'Account Information'),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                children: [
                  _ProfileInfoRow(
                    icon: Icons.person,
                    iconColor: AppSemanticColors.resolve(
                      AppSemanticColors.info,
                      brightness,
                    ),
                    title: 'Full Name',
                    subtitle: user.fullName,
                    isEditable: true,
                    onTap: () => _showEditProfileDialog(user),
                  ),
                  const Divider(height: 1),
                  _ProfileInfoRow(
                    icon: Icons.alternate_email,
                    iconColor: AppSemanticColors.resolve(
                      AppSemanticColors.purple,
                      brightness,
                    ),
                    title: 'Username',
                    subtitle: user.username,
                    isEditable: true,
                    onTap: () => _showEditProfileDialog(user),
                  ),
                  const Divider(height: 1),
                  _ProfileInfoRow(
                    icon: Icons.admin_panel_settings,
                    iconColor: AppSemanticColors.resolve(
                      AppSemanticColors.success,
                      brightness,
                    ),
                    title: 'Role',
                    subtitle: user.role.displayName,
                  ),
                  const Divider(height: 1),
                  _ProfileInfoRow(
                    icon: Icons.calendar_today,
                    iconColor: AppSemanticColors.resolve(
                      AppSemanticColors.warning,
                      brightness,
                    ),
                    title: 'Member Since',
                    subtitle: _formatDateTime(user.createdAt),
                  ),
                  if (user.lastLogin != null) ...[
                    const Divider(height: 1),
                    _ProfileInfoRow(
                      icon: Icons.login,
                      iconColor: AppSemanticColors.resolve(
                        AppSemanticColors.teal,
                        brightness,
                      ),
                      title: 'Last Login',
                      subtitle: _formatDateTime(user.lastLogin!),
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

  // ── HELPERS ───────────────────────────────────────────────────────────

  String _initials(User user) {
    final parts = user.fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return parts.isNotEmpty ? parts[0][0] : '?';
  }

  String _formatDateTime(DateTime value) {
    return value.toLocal().toString().split('.')[0];
  }

  // ── AVATAR ───────────────────────────────────────────────────────────

  Widget _buildAvatar(User user) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.scaffoldBackgroundColor,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(
                  alpha: brightness == Brightness.dark ? 0.28 : 0.22,
                ),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AppAvatar(
            imagePath: user.profileImagePath,
            initials: _initials(user),
            radius: 45,
            semanticLabel: 'Profile picture',
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => _changeProfilePicture(user),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: colorScheme.onPrimary,
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

  Future<void> _showEditProfileDialog(User user) async {
    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.edit,
        title: 'Edit Profile',
        childBuilder: (context, state) {
          final fullNameController =
              state.textController('fullName', text: user.fullName);
          final usernameController =
              state.textController('username', text: user.username);

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextFormField(
                  controller: fullNameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person,
                  validator: (value) =>
                      Validators.required(value, 'Full Name'),
                  onChanged: (_) => state.markChanged(),
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: usernameController,
                  readOnly: user.hasChangedUsername,
                  label: 'Username',
                  prefixIcon: Icons.person_outline,
                  helperText: user.hasChangedUsername
                      ? 'You have already changed your username.'
                      : 'You can only change your username once.',
                  validator: (value) => Validators.compose([
                    (v) => Validators.required(v, 'Username'),
                    (v) => Validators.minLength(v, 3, 'Username'),
                    (v) => Validators.maxLength(v, 50, 'Username'),
                  ], value),
                  onChanged: (_) => state.markChanged(),
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
                : (context) async {
                    if (state.hasChanges) {
                      final discard =
                          await AppDialogService.unsavedChanges(context);
                      if (discard == true && context.mounted) {
                        state.pop(const ModalResult<void>.cancelled());
                      }
                    } else if (context.mounted) {
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
                : (context) async {
                    if (!state.formKey.currentState!.validate()) return;

                    final newUsername =
                        state.textController('username').text.trim();
                    final isChangingUsername = newUsername != user.username;

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
                    state.setSaving(true);
                    final success = await ref
                        .read(authStateProvider.notifier)
                        .updateProfile(
                          userId: user.id!,
                          fullName:
                              state.textController('fullName').text.trim(),
                          username: newUsername,
                        );

                    if (success) {
                      state.pop(const ModalResult<void>.saved());
                    } else {
                      state.setSaving(false);
                      if (context.mounted) {
                        await AppDialogService.error(
                          context,
                          title: 'Update Failed',
                          message: isChangingUsername
                              ? 'Failed to change username. It may already be in use or you may have already changed it.'
                              : 'Failed to update profile.',
                        );
                      }
                    }
                  },
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result case final r? when r.isSaved) {
      final updatedUser = ref.read(authStateProvider).user;
      await AppDialogService.success(
        context,
        title: 'Profile Updated',
        message: updatedUser != null && updatedUser.username != user.username
            ? 'Your profile and username have been updated.'
            : 'Profile updated successfully.',
      );
    } else if (result case final r? when r.isFailed) {
      await AppDialogService.error(
        context,
        title: 'Update Failed',
        message: r.error ?? 'Failed to update profile.',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Local widgets
// ─────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String role;
  final Color color;

  const _RolePill({required this.role, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            role,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isEditable;
  final VoidCallback? onTap;

  const _ProfileInfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isEditable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: _IconBadge(icon: icon, color: iconColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: isEditable
          ? Icon(Icons.edit, size: 20, color: colorScheme.onSurfaceVariant)
          : null,
      onTap: onTap,
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}
