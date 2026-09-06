import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/app_shell.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/screens/splash_screen.dart';
import 'package:pinoy_pos/ui/widgets/session_guard.dart';

/// End-to-end coverage of the required auth/session flow:
///
///   logout -> session cleared -> login screen -> sign in -> profile/role
///   loaded -> role-correct shell -> login route replaced.
///
/// The real [AuthStateNotifier], [SessionGuard], [AuthPhaseNavigator] and
/// [AppShell] run unmodified. Only [AuthService] is faked: its credential
/// path goes through the sqflite FFI background isolate, whose responses
/// are never delivered inside the FakeAsync zone that `testWidgets` uses —
/// so any real-DB await would stall the test forever. The real credential
/// verification path (including owner/admin/staff seed accounts) is covered
/// by `auth_service_session_test.dart`.
class _FakeAuthService extends AuthService {
  /// username -> (user, password)
  final Map<String, (User, String)> credentials;
  String? _lastSignedIn;
  bool _sessionPersisted = false;

  _FakeAuthService(this.credentials);

  @override
  Future<LoginResult> login(String username, String password) async {
    final entry = credentials[username];
    if (entry == null || entry.$2 != password) {
      return LoginResult.invalidCredentials;
    }
    SessionManager().setCurrentUser(entry.$1);
    _lastSignedIn = username;
    _sessionPersisted = true;
    return LoginResult.success;
  }

  @override
  Future<void> logout() async {
    SessionManager().clearCurrentUser();
    _sessionPersisted = false;
    _lastSignedIn = null;
  }

  @override
  Future<SessionStatus> restoreSession() async {
    if (_sessionPersisted && _lastSignedIn != null) {
      SessionManager().setCurrentUser(credentials[_lastSignedIn]!.$1);
      return SessionStatus.active;
    }
    return SessionStatus.none;
  }
}

void main() {
  User makeUser(int id, String username, UserRole role) => User(
        id: id,
        username: username,
        passwordHash: 'x',
        role: role,
        fullName: '${role.displayName} User',
        createdAt: DateTime(2024),
      );

  late _FakeAuthService authService;
  late Map<String, (User, String)> credentials;

  setUpAll(() {
    // The widget tree triggers real DB lookups (dashboard data, session
    // timeout settings). With the default `databaseFactory` uninitialized
    // those calls throw StateError inside unawaited futures and fail the
    // test. With the ffi factory they open the on-disk DB and simply
    // pend inside the FakeAsync zone — harmless, because nothing in these
    // tests awaits them.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
    credentials = {
      'owner': (makeUser(1, 'owner', UserRole.owner), 'owner123'),
      'admin': (makeUser(2, 'admin', UserRole.admin), 'admin123'),
      'staff': (makeUser(3, 'staff', UserRole.staff), 'staff123'),
    };
    authService = _FakeAuthService(credentials);
  });

  ProviderContainer buildContainer() => ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(authService),
      ]);

  Widget buildApp(GlobalKey<NavigatorState> navKey, ProviderContainer c) {
    return UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: navKey,
        theme: AppColors.getLightTheme(),
        darkTheme: AppColors.getDarkTheme(),
        home: const SplashScreen(),
        builder: (context, child) => SessionGuard(
          navigatorKey: navKey,
          child: child!,
        ),
      ),
    );
  }

  /// Signs in through the real login form (text fields + Sign In button).
  ///
  /// The button can sit below the fold on the default test surface, so it
  /// is scrolled into view first. Between `enterText` and the tap we must
  /// not call `pumpAndSettle`: a focused field's blinking cursor keeps
  /// scheduling frames forever. `_login` unfocuses the fields on entry,
  /// which stops the cursor so the settle after the tap can complete.
  Future<void> signInAs(
    WidgetTester tester,
    String username,
    String password,
  ) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), username);
    await tester.enterText(fields.at(1), password);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.pump();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
  }

  testWidgets('cold start with no session lands on the login screen',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(buildApp(navKey, buildContainer()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    // Login must be the only route: pressing back cannot reach an
    // authenticated screen.
    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets(
      'owner login lands on the owner shell with a cleared back stack',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    // Compact width -> NavigationBar with visible role-specific labels.
    tester.view.physicalSize = const Size(420, 840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await signInAs(tester, 'owner', 'owner123');

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    // Owner nav shows POS and Sales (staff sees "My Sales"; admin neither).
    expect(find.text('POS'), findsWidgets);
    expect(find.text('Sales'), findsWidgets);
    expect(container.read(authStateProvider).user?.role, UserRole.owner);
    expect(
        container.read(authStateProvider).phase, AuthSessionPhase.fullyAuthenticated);
    // No login route remains under the shell.
    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets(
      'logout clears the session, returns to login, and back cannot '
      'reopen the dashboard', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();

    await signInAs(tester, 'owner', 'owner123');
    expect(find.byType(AppShell), findsOneWidget);
    expect(SessionManager().currentUser, isNotNull);

    await container.read(authStateProvider.notifier).logout();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(container.read(authStateProvider).user, isNull);
    expect(SessionManager().currentUser, isNull);
    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets('owner -> logout -> admin -> logout -> staff role routing',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    tester.view.physicalSize = const Size(420, 840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();

    await signInAs(tester, 'owner', 'owner123');
    expect(container.read(authStateProvider).user?.role, UserRole.owner);
    expect(find.text('Sales'), findsWidgets);
    expect(find.text('Users'), findsNothing);

    await container.read(authStateProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await signInAs(tester, 'admin', 'admin123');
    expect(container.read(authStateProvider).user?.role, UserRole.admin);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Users'), findsWidgets);
    expect(find.text('POS'), findsNothing);
    expect(navKey.currentState!.canPop(), isFalse);

    await container.read(authStateProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await signInAs(tester, 'staff', 'staff123');
    expect(container.read(authStateProvider).user?.role, UserRole.staff);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('My Sales'), findsWidgets);
    expect(find.text('Users'), findsNothing);
    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets('invalid credentials stay on login and show an error dialog',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();

    await signInAs(tester, 'owner', 'wrong-password');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Login Failed'), findsOneWidget);
    expect(SessionManager().currentUser, isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('relaunch while logged in restores straight to the shell',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();

    await signInAs(tester, 'owner', 'owner123');
    expect(find.byType(AppShell), findsOneWidget);

    // Simulate an app restart: a fresh provider container forces
    // AuthStateNotifier._init -> AuthService.restoreSession again while
    // the persisted session survives.
    final navKey2 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(buildApp(navKey2, buildContainer()));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(navKey2.currentState!.canPop(), isFalse);
  });

  testWidgets('relaunch while logged out shows the login screen',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = buildContainer();
    await tester.pumpWidget(buildApp(navKey, container));
    await tester.pumpAndSettle();

    await signInAs(tester, 'owner', 'owner123');
    await container.read(authStateProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    final navKey2 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(buildApp(navKey2, buildContainer()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
