import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/screens/notifications_screen.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

class _FakeAuthService extends AuthService {
  final User _user;
  _FakeAuthService(this._user);

  @override
  User? get currentUser => _user;

  @override
  bool get isAuthenticated => true;

  @override
  Future<SessionStatus> restoreSession() async => SessionStatus.active;

  @override
  bool hasPermission(String permission) => true;
}

class _TestAuthNotifier extends AuthStateNotifier {
  _TestAuthNotifier(Ref ref, User user) : super(ref, _FakeAuthService(user)) {
    state = AuthState(
      user: user,
      isLoading: false,
      phase: AuthSessionPhase.fullyAuthenticated,
    );
  }
}

void main() {
  final admin = User(
    id: 2,
    username: 'admin',
    passwordHash: 'test-hash',
    role: UserRole.admin,
    fullName: 'Store Admin',
    createdAt: DateTime.now(),
    isActive: true,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  Future<void> pumpPhone(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _TestAuthNotifier(ref, admin)),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('NotificationsScreen empty state centered on phone portrait',
      (tester) async {
    await pumpPhone(tester, const NotificationsScreen());

    expect(find.text('No Notifications'), findsOneWidget);
    final iconCenter = tester.getCenter(find.byIcon(Icons.notifications_none));
    final titleCenter = tester.getCenter(find.text('No Notifications'));
    final emptyBox = tester.getRect(find.byType(EmptyState));
    debugPrint(
        'NOTIF icon=$iconCenter title=$titleCenter emptyRect=$emptyBox');
    expect(iconCenter.dx, closeTo(180, 2));

    // Filter chips must remain visible on the empty screen so the user can
    // switch back to another filter.
    for (final label in const ['All', 'Unread', 'Alerts', 'Announcements']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('AnnouncementsScreen empty state centered on phone portrait',
      (tester) async {
    await pumpPhone(tester, const AnnouncementsScreen());

    expect(find.text('No Announcements Yet'), findsOneWidget);
    final iconCenter = tester.getCenter(find.byIcon(Icons.campaign));
    final titleCenter = tester.getCenter(find.text('No Announcements Yet'));
    final emptyBox = tester.getRect(find.byType(EmptyState));
    debugPrint(
        'ANN icon=$iconCenter title=$titleCenter emptyRect=$emptyBox');
    expect(iconCenter.dx, closeTo(180, 2));
  });

  // Production wraps every route in a Stack (GlobalAIChatOverlay inside
  // MaterialApp.builder). Non-positioned Stack children receive loose
  // constraints — verify the empty state still centers there.
  testWidgets('NotificationsScreen under Stack wrapper stays centered',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _TestAuthNotifier(ref, admin)),
        ],
        child: MaterialApp(
          builder: (context, child) => Stack(children: [child!]),
          home: const NotificationsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No Notifications'), findsOneWidget);
    final iconCenter = tester.getCenter(find.byIcon(Icons.notifications_none));
    final titleCenter = tester.getCenter(find.text('No Notifications'));
    final emptyBox = tester.getRect(find.byType(EmptyState));
    debugPrint(
        'STACK icon=$iconCenter title=$titleCenter emptyRect=$emptyBox');
    expect(iconCenter.dx, closeTo(180, 2));
  });

  // Dump every Text widget's rect on the empty Notifications screen so we
  // can see exactly which text (if any) hugs the left edge.
  testWidgets('dump text positions on empty NotificationsScreen',
      (tester) async {
    await pumpPhone(tester, const NotificationsScreen());

    for (final el in find.byType(Text).evaluate()) {
      final w = el.widget as Text;
      final r = tester.getRect(find.byWidget(w));
      debugPrint('TEXT "${w.data}" rect=$r');
    }
  });

  // Direct probe: EmptyState under a non-positioned Stack child gets loose
  // width (0..maxW) with bounded height — the exact conditions where a
  // shrink-wrapping Column would land on the left.
  testWidgets('Bare EmptyState as non-positioned Stack child', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            EmptyState(
              icon: Icons.notifications_none,
              title: 'No Notifications',
              message: "You're all caught up!",
            ),
          ],
        ),
      ),
    );

    final iconCenter = tester.getCenter(find.byIcon(Icons.notifications_none));
    final titleCenter = tester.getCenter(find.text('No Notifications'));
    final emptyBox = tester.getRect(find.byType(EmptyState));
    debugPrint(
        'BARE-STACK icon=$iconCenter title=$titleCenter emptyRect=$emptyBox');
    expect(iconCenter.dx, closeTo(180, 2));
  });
}
