import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/safe_navigation.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/profile_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';

/// Profile avatar button that opens a dropdown menu with:
///   - Profile (navigate to ProfileScreen)
///   - Settings (navigate to SettingsScreen)
///   - Logout (confirmation dialog → auth logout)
///
/// This is the ONLY profile dropdown structure. Settings, Logout, and
/// other items must NOT be placed as separate header icons.
class ProfileMenu extends ConsumerStatefulWidget {
  const ProfileMenu({super.key});

  @override
  ConsumerState<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends ConsumerState<ProfileMenu> {
  final GlobalKey _avatarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    if (user == null) return const SizedBox.shrink();

    return InkWell(
      key: _avatarKey,
      onTap: () => _showDropdown(user),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: AppAvatar(
          imagePath: user.profileImagePath,
          initials: _initials(user),
          radius: 18,
          semanticLabel: '${user.fullName} profile menu',
        ),
      ),
    );
  }

  void _safePush(Widget screen) {
    SafeNavigator.pushUnique<void>(context, screen);
  }

  String _initials(User user) {
    final parts = user.fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return parts.isNotEmpty ? parts[0][0] : '?';
  }

  void _showDropdown(User user) {
    final renderBox = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<void>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width - 260,
        offset.dy + size.height + 8,
        offset.dx + size.width,
        0,
      ),
      constraints: const BoxConstraints(maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ProfileDropdownContent(
            user: user,
            onProfile: () {
              Navigator.of(context, rootNavigator: true).pop();
              _safePush(const ProfileScreen());
            },
            onSettings: () {
              Navigator.of(context, rootNavigator: true).pop();
              _safePush(const SettingsScreen());
            },
            onLogout: () async {
              Navigator.of(context, rootNavigator: true).pop();
              final confirmed = await AppDialogService.logoutConfirm(context);
              if (confirmed == true && mounted) {
                await ref.read(authStateProvider.notifier).logout();
              }
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dropdown content
// ─────────────────────────────────────────────────────────────────────────

class _ProfileDropdownContent extends StatelessWidget {
  final User user;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  const _ProfileDropdownContent({
    required this.user,
    required this.onProfile,
    required this.onSettings,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User info header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppAvatar(
                  imagePath: user.profileImagePath,
                  initials: user.fullName,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: AppTypography.titleMediumBold(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.role.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Menu items
          _MenuTile(
            icon: Icons.person_outline,
            label: 'Profile',
            onTap: onProfile,
          ),
          const Divider(height: 1),
          _MenuTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: onSettings,
          ),
          const Divider(height: 1),
          _MenuTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            iconColor: colorScheme.error,
            textColor: colorScheme.error,
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
