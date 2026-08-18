import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/screens/access_denied_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Centralized route guard that checks permissions before allowing navigation.
///
/// Usage:
/// ```dart
/// RouteGuard.pushIfAuthorized(
///   context,
///   ref,
///   screen: const UsersScreen(),
///   permission: 'manage_users',
/// );
/// ```
class RouteGuard {
  RouteGuard._();

  /// Checks whether the current user has the given [permission].
  static bool canAccess(WidgetRef ref, String permission) {
    return ref.read(authStateProvider.notifier).hasPermission(permission);
  }

  /// Pushes [screen] via [Navigator.push] only if the current user has
  /// [permission]. Otherwise logs the attempt and shows an Access Denied
  /// dialog.
  static Future<void> pushIfAuthorized(
    BuildContext context,
    WidgetRef ref, {
    required Widget screen,
    required String permission,
    String? routeName,
  }) async {
    if (!canAccess(ref, permission)) {
      await _logAndDeny(context, ref, permission, routeName);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  /// Pushes a replacement route only if authorized.
  static Future<void> pushReplacementIfAuthorized(
    BuildContext context,
    WidgetRef ref, {
    required Widget screen,
    required String permission,
    String? routeName,
  }) async {
    if (!canAccess(ref, permission)) {
      await _logAndDeny(context, ref, permission, routeName);
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  /// Navigates to the [AccessDeniedScreen] and logs the unauthorized attempt.
  static Future<void> _logAndDeny(
    BuildContext context,
    WidgetRef ref,
    String permission,
    String? routeName,
  ) async {
    // Log the unauthorized access attempt
    try {
      final activityLogService = ref.read(activityLogServiceProvider);
      await activityLogService.logActivity(
        action: 'unauthorized_access',
        entity: routeName ?? 'route',
        details: 'Attempted to access resource requiring permission: $permission',
      );
    } catch (_) {
      // Logging is best-effort; don't block the denial
    }

    // Show access denied dialog
    if (context.mounted) {
      AppDialogService.accessDenied(context);
    }
  }
}
