import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// Centralized, semantic quick action identifiers.
///
/// Each [QuickActionType] maps to a single [QuickActionStyle] so every
/// dashboard in the app (Owner, Admin, Staff) uses the same color,
/// icon and label treatment for the same action. The visual identity is
/// defined here; role-specific dashboards only decide whether a type is
/// shown and what it does when tapped.
enum QuickActionType {
  newSale,
  addProduct,
  addStock,
  viewSales,
  mySales,
  reports,
  manageStaff,
  aiAdvisor,
  manageUsers,
  backupRestore,
  trash,
  activityLogs,
  aiConfig,
  settings,
}

/// Theme-aware style for one quick action.
class QuickActionStyle {
  final Color background;
  final Color foreground;
  final IconData icon;
  final String label;

  const QuickActionStyle({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
  });
}

/// Resolves the theme-aware [QuickActionStyle] for a given [type].
QuickActionStyle resolveQuickActionStyle(
  BuildContext context,
  QuickActionType type,
) {
  return resolveQuickActionStyleForBrightness(
    Theme.of(context).brightness,
    type,
  );
}

/// Resolves a [QuickActionStyle] for a specific brightness without a
/// [BuildContext]. Useful in tests and golden builders.
QuickActionStyle resolveQuickActionStyleForBrightness(
  Brightness brightness,
  QuickActionType type,
) {
  final family = _familyForType(type);
  final background = AppSemanticColors.resolveSurface(family.surface, brightness);
  final foreground = AppSemanticColors.contrastFor(background, brightness);
  final (icon, label) = _defaultsFor(type);

  return QuickActionStyle(
    background: background,
    foreground: foreground,
    icon: icon,
    label: label,
  );
}

class _QuickActionColorFamily {
  final Color surface;

  const _QuickActionColorFamily({
    required this.surface,
  });
}

const _QuickActionColorFamily _primaryFamily = _QuickActionColorFamily(
  surface: AppSemanticColors.primarySurface,
);

const _QuickActionColorFamily _successFamily = _QuickActionColorFamily(
  surface: AppSemanticColors.successSurface,
);

const _QuickActionColorFamily _infoFamily = _QuickActionColorFamily(
  surface: AppSemanticColors.infoSurface,
);

const _QuickActionColorFamily _warningFamily = _QuickActionColorFamily(
  surface: AppSemanticColors.warningSurface,
);

const _QuickActionColorFamily _neutralFamily = _QuickActionColorFamily(
  surface: AppSemanticColors.neutralSurface,
);

_QuickActionColorFamily _familyForType(QuickActionType type) {
  return switch (type) {
    QuickActionType.newSale => _successFamily,
    QuickActionType.addProduct => _infoFamily,
    QuickActionType.addStock => _infoFamily,
    QuickActionType.viewSales => _primaryFamily,
    QuickActionType.mySales => _successFamily,
    QuickActionType.reports => _primaryFamily,
    QuickActionType.manageStaff => _primaryFamily,
    QuickActionType.aiAdvisor => _infoFamily,
    QuickActionType.manageUsers => _primaryFamily,
    QuickActionType.backupRestore => _infoFamily,
    QuickActionType.trash => _warningFamily,
    QuickActionType.activityLogs => _neutralFamily,
    QuickActionType.aiConfig => _infoFamily,
    QuickActionType.settings => _neutralFamily,
  };
}

(IconData, String) _defaultsFor(QuickActionType type) {
  return switch (type) {
    QuickActionType.newSale => (Icons.point_of_sale, 'New Sale'),
    QuickActionType.addProduct => (Icons.add_box_outlined, 'Add Product'),
    QuickActionType.addStock => (Icons.warehouse_outlined, 'Add Stock'),
    QuickActionType.viewSales => (Icons.receipt_long, 'View Sales'),
    QuickActionType.mySales => (Icons.receipt_long, 'My Sales'),
    QuickActionType.reports => (Icons.analytics_outlined, 'Reports'),
    QuickActionType.manageStaff => (Icons.people, 'Manage Staff'),
    QuickActionType.aiAdvisor => (Icons.auto_awesome, 'AI Advisor'),
    QuickActionType.manageUsers => (Icons.people, 'Manage Users'),
    QuickActionType.backupRestore => (Icons.backup, 'Backup & Restore'),
    QuickActionType.trash => (Icons.delete_outline, 'Trash'),
    QuickActionType.activityLogs => (Icons.history, 'Activity Logs'),
    QuickActionType.aiConfig => (Icons.psychology_outlined, 'AI Config'),
    QuickActionType.settings => (Icons.settings, 'Settings'),
  };
}
