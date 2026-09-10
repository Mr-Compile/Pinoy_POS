import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// Logical category for a notification. Used to drive filtering and icon color.
enum NotificationCategory {
  alert,
  announcement,
  report,
  backup,
  payment,
  system,
  unknown,
}

/// Visual style for a notification, resolved from its [type].
class NotificationStyle {
  final IconData icon;
  final Color color;
  final NotificationCategory category;

  const NotificationStyle._(this.icon, this.color, this.category);

  /// Resolves the style for a given notification [type].
  ///
  /// [colorScheme] and [brightness] are required so the returned [color]
  /// is theme-aware.
  factory NotificationStyle.fromType(
    String? type,
    ColorScheme colorScheme,
    Brightness brightness,
  ) {
    switch (type) {
      case 'low_stock':
        return NotificationStyle._(
          Icons.warning_amber_rounded,
          AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
          NotificationCategory.alert,
        );
      case 'out_of_stock':
        return NotificationStyle._(
          Icons.error_outline,
          AppSemanticColors.resolve(AppSemanticColors.error, brightness),
          NotificationCategory.alert,
        );
      case 'announcement':
        return NotificationStyle._(
          Icons.campaign_outlined,
          AppSemanticColors.resolve(AppSemanticColors.violet, brightness),
          NotificationCategory.announcement,
        );
      case 'report_submitted':
        return NotificationStyle._(
          Icons.bar_chart,
          AppSemanticColors.resolve(AppSemanticColors.info, brightness),
          NotificationCategory.report,
        );
      case 'backup':
        return NotificationStyle._(
          Icons.backup_outlined,
          AppSemanticColors.resolve(AppSemanticColors.success, brightness),
          NotificationCategory.backup,
        );
      case 'payment':
      case 'payment_verified':
        return NotificationStyle._(
          Icons.receipt_long_outlined,
          AppSemanticColors.resolve(AppSemanticColors.teal, brightness),
          NotificationCategory.payment,
        );
      case 'system':
        return NotificationStyle._(
          Icons.settings_outlined,
          AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
          NotificationCategory.system,
        );
      default:
        return NotificationStyle._(
          Icons.info_outline,
          colorScheme.primary,
          NotificationCategory.unknown,
        );
    }
  }
}
