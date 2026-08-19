import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/notification_bell.dart';
import 'package:pinoy_pos/ui/widgets/profile_menu.dart';

/// Reusable global app header (AppBar) that provides:
///
///   LEFT:  [title] (or [leading] + [title] for pushed screens)
///   RIGHT: Notification bell + Profile avatar
///
/// All authenticated screens should use [AppHeader] as their AppBar so
/// the notification bell and profile menu are consistently available
/// across the entire application.
///
/// Example (main tab screen — no back button):
/// ```dart
/// Scaffold(
///   appBar: AppHeader(title: 'Dashboard'),
///   body: ...,
/// )
/// ```
///
/// Example (pushed screen — with back button):
/// ```dart
/// Scaffold(
///   appBar: AppHeader(title: 'Profile', showBackButton: true),
///   body: ...,
/// )
/// ```
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final bool showNotificationBell;
  final bool showProfileMenu;
  final PreferredSizeWidget? bottom;

  const AppHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.actions,
    this.showNotificationBell = true,
    this.showProfileMenu = true,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final headerActions = <Widget>[
      ...?actions,
      if (showNotificationBell) const NotificationBell(),
      if (showProfileMenu) const ProfileMenu(),
    ];

    return AppBar(
      title: Text(title),
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      actions: headerActions,
      bottom: bottom,
    );
  }
}
