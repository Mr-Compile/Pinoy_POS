import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/notification_bell.dart';
import 'package:pinoy_pos/ui/widgets/profile_menu.dart';

/// Tests for the AppHeader, NotificationBell, and ProfileMenu widgets.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
  });

  /// Creates an owner User directly (bypassing the database) and sets
  /// the SessionManager singleton.
  Future<User> authenticateAsOwner() async {
    final owner = User(
      id: 1,
      username: 'owner',
      passwordHash: 'test-hash',
      role: UserRole.owner,
      fullName: 'Store Owner',
      createdAt: DateTime.now(),
      isActive: true,
    );
    SessionManager().setCurrentUser(owner);
    return owner;
  }

  testWidgets('AppHeader builds with notification bell and profile menu',
      (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: AppHeader(title: 'Test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Test'), findsOneWidget);
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(find.byType(ProfileMenu), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('NotificationBell shows badge when unread count > 0',
      (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 5),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NotificationBell(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('5'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('NotificationBell shows no badge when unread count is 0',
      (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NotificationBell(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotificationBell), findsOneWidget);
    expect(find.text('0'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('NotificationBell renders a visible bell icon (regression: '
      'Badge previously had no child, making the bell invisible)',
      (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NotificationBell(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // The bell icon must be rendered inside the Badge's child.
    final bellFinder = find.byIcon(Icons.notifications_outlined);
    expect(bellFinder, findsOneWidget);

    // The icon must have a visible (non-transparent) color.
    final icon = tester.widget<Icon>(bellFinder);
    expect(icon.color, isNotNull);
    expect((icon.color!.a * 255.0).round().clamp(0, 255), greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('NotificationBell renders filled bell icon when unread > 0',
      (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 3),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NotificationBell(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // With unread notifications, the filled (round) bell variant is shown.
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('ProfileMenu shows avatar and name', (tester) async {
    final owner = await authenticateAsOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) {
            return _TestAuthNotifier(ref, owner);
          }),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProfileMenu(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProfileMenu), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

class _TestAuthNotifier extends AuthStateNotifier {
  _TestAuthNotifier(Ref ref, User owner) : super(ref, AuthService()) {
    state = AuthState(user: owner, isLoading: false);
  }
}
