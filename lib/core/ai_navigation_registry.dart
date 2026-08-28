import 'package:flutter/material.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/dashboard_screen.dart';
import 'package:pinoy_pos/ui/screens/more_screen.dart';
import 'package:pinoy_pos/ui/screens/notifications_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/profile_screen.dart';
import 'package:pinoy_pos/ui/screens/receipt_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_config_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_quota_management_page.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';

/// A single, application-registered destination that the AI assistant is
/// allowed to navigate the user to.
///
/// The AI can *request* a destination, but the application resolves and
/// validates it against [requiredPermission] and [allowedRoles] before
/// any [Widget] is built or any [Navigator] call is made.
class AIDestination {
  final String id;
  final String displayName;
  final String description;
  final String requiredPermission;
  final List<UserRole> allowedRoles;
  final WidgetBuilder builder;

  /// Optional builder for a detail view that requires parameters.
  /// If this is set, the destination is treated as a contextual deep link.
  final Widget Function(BuildContext, Map<String, dynamic> params)? detailBuilder;

  /// Human-readable steps for how to use this feature. Used when the AI
  /// produces step-by-step guidance without making an external API call.
  final List<String> howToSteps;

  /// Other destination IDs that are reasonable follow-up actions after
  /// navigating here (e.g., after "sales" suggest "reports" or "products").
  final List<String> relatedDestinations;

  const AIDestination({
    required this.id,
    required this.displayName,
    required this.description,
    required this.requiredPermission,
    this.allowedRoles = const [],
    required this.builder,
    this.detailBuilder,
    this.howToSteps = const [],
    this.relatedDestinations = const [],
  });

  /// Returns the screen widget for this destination.
  ///
  /// [params] is only used when [detailBuilder] is supplied.
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    if (detailBuilder != null && params != null) {
      return detailBuilder!(context, params);
    }
    return builder(context);
  }
}

/// The central registry of all AI-navigable destinations.
///
/// This is the only place in the application that maps from a short
/// destination ID to a real screen. The AI never gets raw route strings.
class AINavigationRegistry {
  AINavigationRegistry._();

  /// All registered destinations keyed by [id].
  static final Map<String, AIDestination> _destinations = {
    for (final d in _allDestinations) d.id: d,
  };

  /// Returns the destination with [id], or null if it is not registered.
  static AIDestination? get(String id) => _destinations[id];

  /// Returns all registered destination IDs.
  static List<String> get ids => _destinations.keys.toList();

  /// Returns all destinations the given [roles] and [hasPermission] allow.
  static List<AIDestination> allowedFor(
    UserRole? role,
    bool Function(String) hasPermission,
  ) {
    return _destinations.values.where((d) {
      if (d.allowedRoles.isNotEmpty && !d.allowedRoles.contains(role)) {
        return false;
      }
      return hasPermission(d.requiredPermission);
    }).toList();
  }

  /// True if [id] is a registered destination.
  static bool isRegistered(String id) => _destinations.containsKey(id);

  static final List<AIDestination> _allDestinations = [
    const AIDestination(
      id: 'dashboard',
      displayName: 'Dashboard',
      description: 'Overview of today’s sales, stock alerts, and key metrics.',
      requiredPermission: 'view_dashboard',
      builder: _dashboardBuilder,
      howToSteps: [
        'Open the Dashboard from the bottom navigation.',
        'Review today’s sales and low-stock alerts.',
      ],
      relatedDestinations: ['sales', 'products', 'reports'],
    ),
    const AIDestination(
      id: 'pos',
      displayName: 'POS',
      description: 'Create new sales and process customer payments.',
      requiredPermission: 'view_pos',
      builder: _posBuilder,
      howToSteps: [
        'Open the POS screen.',
        'Tap a product to add it to the cart.',
        'Tap Checkout and choose the payment method.',
        'Confirm the payment to complete the sale.',
      ],
      relatedDestinations: ['sales', 'products'],
    ),
    const AIDestination(
      id: 'products',
      displayName: 'Products',
      description: 'View, add, edit, and delete products.',
      requiredPermission: 'view_products',
      builder: _productsBuilder,
      howToSteps: [
        'Open Products.',
        'Tap Add Product or select an existing product.',
        'Enter product details, price, and stock.',
        'Tap Save.',
      ],
      relatedDestinations: ['categories', 'stock', 'pos'],
    ),
    const AIDestination(
      id: 'categories',
      displayName: 'Categories',
      description: 'Organize products into categories.',
      requiredPermission: 'view_categories',
      builder: _categoriesBuilder,
      howToSteps: [
        'Open Categories from the More screen.',
        'Tap Add Category.',
        'Enter the category name.',
        'Tap Save.',
      ],
      relatedDestinations: ['products', 'stock'],
    ),
    const AIDestination(
      id: 'stock',
      displayName: 'Stock / Inventory',
      description: 'Check stock levels, low-stock items, and adjust inventory.',
      requiredPermission: 'view_stock',
      builder: _stockBuilder,
      howToSteps: [
        'Open Stock from the More screen.',
        'Review the stock list and low-stock alerts.',
        'Select a product and choose Adjust Stock.',
        'Enter the new quantity or adjustment and save.',
      ],
      relatedDestinations: ['products', 'reports'],
    ),
    const AIDestination(
      id: 'sales',
      displayName: 'Sales',
      description: 'View and manage sales transactions.',
      requiredPermission: 'view_sales',
      builder: _salesBuilder,
      howToSteps: [
        'Open Sales.',
        'Scroll through the list or use the search bar.',
        'Tap a sale to see details or a receipt.',
      ],
      relatedDestinations: ['pos', 'reports', 'receipt'],
    ),
    const AIDestination(
      id: 'sale_details',
      displayName: 'Sale Details',
      description: 'View a specific sale transaction.',
      requiredPermission: 'view_sales',
      builder: _saleDetailsFallbackBuilder,
      detailBuilder: _saleDetailsBuilder,
      howToSteps: [
        'Open Sales.',
        'Find the transaction and tap it.',
      ],
      relatedDestinations: ['sales', 'receipt'],
    ),
    const AIDestination(
      id: 'receipt',
      displayName: 'Receipt',
      description: 'View or share a receipt for a completed sale.',
      requiredPermission: 'view_sales',
      builder: _receiptFallbackBuilder,
      detailBuilder: _receiptBuilder,
      howToSteps: [
        'Open Sales and select a transaction.',
        'Tap View Receipt.',
      ],
      relatedDestinations: ['sales', 'sale_details'],
    ),
    const AIDestination(
      id: 'reports',
      displayName: 'Reports',
      description: 'Analyze sales, products, and export data.',
      requiredPermission: 'view_reports',
      builder: _reportsBuilder,
      howToSteps: [
        'Open Reports from the More screen.',
        'Choose the report type and date range.',
        'Tap Generate or Export.',
      ],
      relatedDestinations: ['sales', 'products', 'dashboard'],
    ),
    const AIDestination(
      id: 'users',
      displayName: 'User Management',
      description: 'Add, edit, and manage staff and admin accounts.',
      requiredPermission: 'manage_users',
      allowedRoles: [UserRole.owner, UserRole.admin],
      builder: _usersBuilder,
      howToSteps: [
        'Open User Management.',
        'Tap Add User.',
        'Enter the username, full name, and role.',
        'Tap Save.',
      ],
      relatedDestinations: ['settings', 'activity_logs'],
    ),
    const AIDestination(
      id: 'settings',
      displayName: 'Settings',
      description: 'Configure application preferences and store details.',
      requiredPermission: 'view_settings',
      builder: _settingsBuilder,
      howToSteps: [
        'Open Settings.',
        'Select the section you want to change.',
        'Update the fields and save.',
      ],
      relatedDestinations: ['ai_settings', 'backup_restore', 'profile'],
    ),
    const AIDestination(
      id: 'ai_settings',
      displayName: 'AI Configuration',
      description: 'Configure the AI model and API key.',
      requiredPermission: 'manage_ai_config',
      builder: _aiConfigBuilder,
      howToSteps: [
        'Open Settings and select AI Configuration.',
        'Enter or update the Groq API key.',
        'Choose the model and tap Save.',
      ],
      relatedDestinations: ['settings'],
    ),
    const AIDestination(
      id: 'ai_quota',
      displayName: 'AI Quota Management',
      description: 'Manage daily AI query quotas for users.',
      requiredPermission: 'edit_settings',
      allowedRoles: [UserRole.owner, UserRole.admin],
      builder: _aiQuotaBuilder,
      howToSteps: [
        'Open Settings and select AI Quota Management.',
        'Review the default and per-user quotas.',
        'Edit a quota and confirm with the SuperAdmin password.',
      ],
      relatedDestinations: ['settings', 'users'],
    ),
    const AIDestination(
      id: 'backup_restore',
      displayName: 'Backup & Restore',
      description: 'Create and restore database backups.',
      requiredPermission: 'backup_restore',
      allowedRoles: [UserRole.owner, UserRole.admin],
      builder: _backupRestoreBuilder,
      howToSteps: [
        'Open Settings and select Backup & Restore.',
        'Tap Create Backup to save a copy.',
        'To restore, choose a backup file and confirm.',
      ],
      relatedDestinations: ['settings'],
    ),
    const AIDestination(
      id: 'activity_logs',
      displayName: 'Activity Logs',
      description: 'View system and user activity history.',
      requiredPermission: 'view_activity_logs',
      builder: _activityLogsBuilder,
      howToSteps: [
        'Open Settings and select Activity Logs.',
        'Scroll or filter to find the event.',
      ],
      relatedDestinations: ['settings', 'users'],
    ),
    const AIDestination(
      id: 'trash',
      displayName: 'Trash Bin',
      description: 'Restore or permanently delete removed items.',
      requiredPermission: 'view_trash',
      builder: _trashBuilder,
      howToSteps: [
        'Open Settings and select Trash Bin.',
        'Select an item and choose Restore or Delete.',
      ],
      relatedDestinations: ['settings'],
    ),
    const AIDestination(
      id: 'profile',
      displayName: 'Profile',
      description: 'View and edit your account information.',
      requiredPermission: 'view_profile',
      builder: _profileBuilder,
      howToSteps: [
        'Open Settings and select Profile.',
        'Update your name, password, or PIN.',
        'Tap Save.',
      ],
      relatedDestinations: ['settings'],
    ),
    const AIDestination(
      id: 'notifications',
      displayName: 'Notifications',
      description: 'View system and payment notifications.',
      requiredPermission: 'view_notifications',
      builder: _notificationsBuilder,
      howToSteps: [
        'Open Notifications.',
        'Tap a notification to view details.',
      ],
      relatedDestinations: ['dashboard'],
    ),
    const AIDestination(
      id: 'announcements',
      displayName: 'Announcements',
      description: 'View store announcements and notices.',
      requiredPermission: 'view_announcements',
      builder: _announcementsBuilder,
      howToSteps: [
        'Open Announcements from the More screen.',
        'Read the pinned and recent announcements.',
      ],
      relatedDestinations: ['more'],
    ),
    const AIDestination(
      id: 'more',
      displayName: 'More',
      description: 'Access additional features and secondary screens.',
      requiredPermission: 'view_more',
      builder: _moreBuilder,
      howToSteps: [
        'Open More from the bottom navigation.',
        'Select the feature you want.',
      ],
      relatedDestinations: ['categories', 'stock', 'reports', 'announcements'],
    ),
  ];

  // ── Widget builders ──────────────────────────────────────────────────

  static Widget _dashboardBuilder(BuildContext context) => const DashboardScreen();
  static Widget _posBuilder(BuildContext context) => const POSScreen();
  static Widget _productsBuilder(BuildContext context) => const ProductsScreen();
  static Widget _categoriesBuilder(BuildContext context) => const CategoriesScreen();
  static Widget _stockBuilder(BuildContext context) => const StockScreen();
  static Widget _salesBuilder(BuildContext context) => const SalesScreen();
  static Widget _reportsBuilder(BuildContext context) => const ReportsScreen();
  static Widget _usersBuilder(BuildContext context) => const UsersScreen();
  static Widget _settingsBuilder(BuildContext context) => const SettingsScreen();
  static Widget _aiConfigBuilder(BuildContext context) => const AIConfigScreen();
  static Widget _aiQuotaBuilder(BuildContext context) => const AIQuotaManagementPage();
  static Widget _backupRestoreBuilder(BuildContext context) => const BackupRestoreScreen();
  static Widget _activityLogsBuilder(BuildContext context) => const ActivityLogsScreen();
  static Widget _trashBuilder(BuildContext context) => const TrashScreen();
  static Widget _profileBuilder(BuildContext context) => const ProfileScreen();
  static Widget _notificationsBuilder(BuildContext context) => const NotificationsScreen();
  static Widget _announcementsBuilder(BuildContext context) => const AnnouncementsScreen();
  static Widget _moreBuilder(BuildContext context) => const MoreScreen();

  static Widget _saleDetailsBuilder(
    BuildContext context,
    Map<String, dynamic> params,
  ) {
    final saleId = parseSaleId(params['saleId']);
    if (saleId == null) return const SalesScreen();
    return SaleDetailScreen(saleId: saleId);
  }

  static Widget _receiptBuilder(
    BuildContext context,
    Map<String, dynamic> params,
  ) {
    final saleId = parseSaleId(params['saleId']);
    if (saleId == null) return const SalesScreen();
    return ReceiptScreen(saleId: saleId);
  }

  static int? parseSaleId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value > 0 ? value : null;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }

  static Widget _saleDetailsFallbackBuilder(BuildContext context) => const SalesScreen();

  static Widget _receiptFallbackBuilder(BuildContext context) => const SalesScreen();
}
