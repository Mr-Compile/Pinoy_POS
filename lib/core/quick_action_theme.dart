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
///
/// [background] and [foreground] are resolved for the current brightness.
/// The foreground is chosen from actual contrast, not a hardcoded "white on
/// everything" assumption, so light amber and cyan backgrounds get black
/// text while deep blue/purple backgrounds get white text.
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
///
/// This is the single source of truth for quick action colors, typography
/// contrast and default labels across the entire app.
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
  final background = family.surface(brightness);
  final foreground = AppSemanticColors.contrastFor(background);
  final (icon, label) = _defaultsFor(type);

  return QuickActionStyle(
    background: background,
    foreground: foreground,
    icon: icon,
    label: label,
  );
}

class _QuickActionColorFamily {
  final Color lightSurface;
  final Color darkSurface;

  const _QuickActionColorFamily({
    required this.lightSurface,
    required this.darkSurface,
  });

  Color surface(Brightness brightness) {
    return brightness == Brightness.light ? lightSurface : darkSurface;
  }
}

const _QuickActionColorFamily _blueFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.primarySurface, // Blue 500
  darkSurface: Color(0xFF1E3A8A), // Blue 900
);

const _QuickActionColorFamily _tealFamily = _QuickActionColorFamily(
  lightSurface: Color(0xFF14B8A6), // Teal 500
  darkSurface: Color(0xFF115E59), // Teal 900
);

const _QuickActionColorFamily _greenFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.successSurface, // Emerald 700
  darkSurface: Color(0xFF065F46), // Emerald 900
);

const _QuickActionColorFamily _cyanFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.infoSurface, // Cyan 500
  darkSurface: Color(0xFF155E75), // Cyan 900
);

const _QuickActionColorFamily _amberFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.warningSurface, // Amber 500
  darkSurface: Color(0xFF92400E), // Amber 900
);

const _QuickActionColorFamily _indigoFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.secondarySurface, // Indigo 500
  darkSurface: Color(0xFF312E81), // Indigo 900
);

const _QuickActionColorFamily _purpleFamily = _QuickActionColorFamily(
  lightSurface: Color(0xFF8B5CF6), // Violet 500
  darkSurface: Color(0xFF5B21B6), // Violet 800
);

const _QuickActionColorFamily _violetFamily = _QuickActionColorFamily(
  lightSurface: Color(0xFF7C3AED), // Violet 600
  darkSurface: Color(0xFF4C1D95), // Violet 900
);

const _QuickActionColorFamily _slateFamily = _QuickActionColorFamily(
  lightSurface: AppSemanticColors.neutralSurface, // Slate 600
  darkSurface: Color(0xFF334155), // Slate 700
);

_QuickActionColorFamily _familyForType(QuickActionType type) {
  return switch (type) {
    QuickActionType.newSale => _greenFamily,
    QuickActionType.addProduct => _cyanFamily,
    QuickActionType.addStock => _cyanFamily,
    QuickActionType.viewSales => _greenFamily,
    QuickActionType.mySales => _greenFamily,
    QuickActionType.reports => _indigoFamily,
    QuickActionType.manageStaff => _blueFamily,
    QuickActionType.aiAdvisor => _violetFamily,
    QuickActionType.manageUsers => _blueFamily,
    QuickActionType.backupRestore => _tealFamily,
    QuickActionType.trash => _amberFamily,
    QuickActionType.activityLogs => _purpleFamily,
    QuickActionType.aiConfig => _violetFamily,
    QuickActionType.settings => _slateFamily,
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
