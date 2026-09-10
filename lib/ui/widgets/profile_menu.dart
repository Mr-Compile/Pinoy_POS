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
      borderRadius: BorderRadius.circular(AppRadius.xl),
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
    final renderBox =
        _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final screenSize = MediaQuery.of(context).size;
    const maxMenuWidth = 260.0;
    final desiredLeft = offset.dx + size.width - maxMenuWidth;
    final maxLeft = (screenSize.width - maxMenuWidth).clamp(
      0.0,
      double.infinity,
    );
    final left = desiredLeft.clamp(0.0, maxLeft);
    final right = (screenSize.width - left - maxMenuWidth).clamp(
      0.0,
      double.infinity,
    );

    final brightness = Theme.of(context).brightness;
    final primaryColor = AppSemanticColors.resolve(
      AppSemanticColors.primary,
      brightness,
    );

    showMenu<void>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        left,
        offset.dy + size.height + 8,
        right,
        0,
      ),
      constraints: const BoxConstraints(maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.menu),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ProfileDropdownContent(
            user: user,
            primaryColor: primaryColor,
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
  final Color primaryColor;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  const _ProfileDropdownContent({
    required this.user,
    required this.primaryColor,
    required this.onProfile,
    required this.onSettings,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final successColor = AppSemanticColors.resolve(
      AppSemanticColors.success,
      brightness,
    );
    final errorColor = AppSemanticColors.resolve(
      AppSemanticColors.error,
      brightness,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 260),
      child: IntrinsicWidth(
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.fullName,
                        style: AppTypography.titleMediumBold(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _RolePill(
                        role: user.role.displayName,
                        color: successColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Menu items
            _MenuTile(
              icon: Icons.person_outline,
              label: 'Profile',
              iconColor: primaryColor,
              onTap: onProfile,
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              iconColor: primaryColor,
              onTap: onSettings,
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.logout_rounded,
              label: 'Logout',
              iconColor: errorColor,
              textColor: errorColor,
              onTap: onLogout,
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            role,
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
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: resolvedIconColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: resolvedIconColor),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
