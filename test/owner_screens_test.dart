import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/screens/dashboard_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/profile_screen.dart';
import 'package:pinoy_pos/ui/screens/more_screen.dart';

/// Widget tests that verify every Owner screen can build and render without
/// throwing Riverpod or runtime errors.
///
/// Each test:
///   1. Initialises a fresh SQLite database (via sqflite_ffi).
///   2. Seeds the default owner user.
///   3. Authenticates as owner (sets SessionManager + SharedPreferences).
///   4. Pumps the screen inside a ProviderScope and asserts no exception.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Close any existing database connection first so the file handle is
    // released before we re-open.
    await DatabaseHelper.resetForTest();
    // Brief pause to let Windows release the file handle before re-opening.
    await Future.delayed(const Duration(milliseconds: 200));

    // Open the database.  If the file already exists (Windows file lock
    // prevents deletion between tests), the tables will already be present
    // and the seeder is idempotent (checks for existing users before
    // inserting), so this is safe.
    final dbHelper = DatabaseHelper();
    await dbHelper.database;

    final seeder = DatabaseSeeder();
    await seeder.seed();

    // Clean SharedPreferences.
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    // Use resetForTest (not close()) so the singleton is fully cleared
    // between tests.  close() re-opens the database if it was already
    // closed, which can leave a dangling handle on Windows.
    await DatabaseHelper.resetForTest();
    // Brief pause to let Windows release the file handle.
    await Future.delayed(const Duration(milliseconds: 200));
  });

  /// Helper: authenticates as the seeded owner and returns the User.
  /// This sets the SessionManager singleton so all services see the owner.
  Future<User> authenticateAsOwner() async {
    final authService = AuthService();
    final success = await authService.login('owner', 'owner123');
    if (!success) {
      throw StateError('Owner login failed');
    }
    return authService.currentUser!;
  }

  /// Helper: pumps [screen] inside a ProviderScope with the owner
  /// authenticated, and verifies it builds without throwing.
  ///
  /// Uses [pump] with a fixed duration instead of [pumpAndSettle] because
  /// loading states contain indeterminate progress indicators that
  /// schedule frames forever, causing pumpAndSettle to time out.
  Future<void> pumpOwnerScreen(
    WidgetTester tester,
    Widget screen, {
    required User owner,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            final notifier = _TestAuthNotifier(owner);
            return notifier;
          }),
        ],
        child: MaterialApp(
          home: screen,
        ),
      ),
    );
    // Pump several frames to let async initState loading complete.
    // We use pump (not pumpAndSettle) because CircularProgressIndicator
    // schedules frames indefinitely.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('DashboardScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const DashboardScreen(), owner: owner);
    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('POSScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const POSScreen(), owner: owner);
    expect(find.text('POS'), findsWidgets);
  });

  testWidgets('ProductsScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const ProductsScreen(), owner: owner);
    expect(find.text('Products'), findsWidgets);
  });

  testWidgets('CategoriesScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const CategoriesScreen(), owner: owner);
    expect(find.text('Categories'), findsWidgets);
  });

  testWidgets('StockScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const StockScreen(), owner: owner);
    expect(find.text('Stock Management'), findsWidgets);
  });

  testWidgets('SalesScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const SalesScreen(), owner: owner);
    expect(find.text('Sales'), findsWidgets);
  });

  testWidgets('ReportsScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const ReportsScreen(), owner: owner);
    expect(find.text('Reports'), findsWidgets);
  });

  testWidgets('AnnouncementsScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const AnnouncementsScreen(), owner: owner);
    expect(find.text('Announcements'), findsWidgets);
  });

  testWidgets('TrashScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const TrashScreen(), owner: owner);
    expect(find.text('Trash Bin'), findsWidgets);
  });

  testWidgets('ActivityLogsScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const ActivityLogsScreen(), owner: owner);
    expect(find.text('Activity Logs'), findsWidgets);
  });

  testWidgets('AIAdvisorScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const AIAdvisorScreen(), owner: owner);
    expect(find.text('AI Business Advisor'), findsOneWidget);
  });

  testWidgets('SettingsScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const SettingsScreen(), owner: owner);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('ProfileScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const ProfileScreen(), owner: owner);
    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets('MoreScreen builds for owner', (tester) async {
    final owner = await authenticateAsOwner();
    await pumpOwnerScreen(tester, const MoreScreen(), owner: owner);
    expect(find.text('More'), findsWidgets);
  });
}

class _TestAuthNotifier extends AuthStateNotifier {
  _TestAuthNotifier(User owner)
      : super(AuthService(), ThemeNotifier()) {
    state = AuthState(user: owner, isLoading: false);
  }
}
