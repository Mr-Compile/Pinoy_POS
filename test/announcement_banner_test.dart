import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/announcement_dao.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/notification_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/announcement_service.dart';
import 'package:pinoy_pos/ui/widgets/announcement_banner.dart';

/// Tests for the announcement banner and the Staff + Admin notification
/// fan-out when the Owner posts an announcement.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();
    await DatabaseSeeder().seed();
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
  });

  Future<User> authenticateAs(String username) async {
    final user = await UserRepository().getByUsername(username);
    if (user == null) throw StateError('Seeded $username not found');
    SessionManager().setCurrentUser(user);
    return user;
  }

  Future<int> insertPinned({String title = 'Pinned', bool expired = false}) {
    return AnnouncementDao().insert(Announcement(
      title: title,
      content: 'Content for $title',
      isPinned: true,
      expiresAt: expired
          ? DateTime.now().subtract(const Duration(days: 1))
          : null,
      createdAt: DateTime.now(),
    ));
  }

  group('createAnnouncement notification fan-out', () {
    test('notifies staff and admin, not the owner', () async {
      final owner = await authenticateAs('owner');
      final service = AnnouncementService();

      final ok = await service.createAnnouncement(
        title: 'Store closed Sunday',
        content: 'No operations for the fiesta.',
      );
      expect(ok, isTrue);

      final notifRepo = NotificationRepository();
      final users = UserRepository();
      final staff = (await users.getByUsername('staff'))!;
      final admin = (await users.getByUsername('admin'))!;

      final staffNotifs = await notifRepo.getByUserId(staff.id!);
      final adminNotifs = await notifRepo.getByUserId(admin.id!);
      final ownerNotifs = await notifRepo.getByUserId(owner.id!);

      expect(
        staffNotifs.where((n) =>
            n.type == 'announcement' &&
            n.title == 'New Announcement: Store closed Sunday'),
        hasLength(1),
      );
      expect(
        adminNotifs.where((n) =>
            n.type == 'announcement' &&
            n.title == 'New Announcement: Store closed Sunday'),
        hasLength(1),
      );
      // Admin receives the full content (no Announcements screen access).
      expect(
        adminNotifs.firstWhere((n) => n.type == 'announcement').message,
        'No operations for the fiesta.',
      );
      expect(
        ownerNotifs.where((n) => n.type == 'announcement'),
        isEmpty,
      );
    });
  });

  group('getBannerAnnouncements', () {
    test('returns pinned announcements for staff (auth-only, no '
        'view_announcements permission)', () async {
      await authenticateAs('staff');
      await insertPinned(title: 'Fiesta closure');

      final items = await AnnouncementService().getBannerAnnouncements();
      expect(items.map((a) => a.title), contains('Fiesta closure'));
    });

    test('excludes expired pinned announcements', () async {
      await authenticateAs('staff');
      await insertPinned(title: 'Live', expired: false);
      await insertPinned(title: 'Expired', expired: true);

      final items = await AnnouncementService().getBannerAnnouncements();
      expect(items.map((a) => a.title), contains('Live'));
      expect(items.map((a) => a.title), isNot(contains('Expired')));
    });

    test('returns empty when unauthenticated', () async {
      SessionManager.resetForTest();
      await insertPinned();
      expect(await AnnouncementService().getBannerAnnouncements(), isEmpty);
    });
  });

  group('banner dismissal', () {
    test('dismiss persists per user and does not leak to other users',
        () async {
      final staff = await authenticateAs('staff');
      final id = await insertPinned();
      final service = AnnouncementService();

      expect(await service.getDismissedBannerIds(), isEmpty);
      await service.dismissBannerAnnouncement(id);
      expect(await service.getDismissedBannerIds(), contains(id));

      // A different user on the same device keeps an empty dismiss set.
      await authenticateAs('admin');
      expect(await service.getDismissedBannerIds(), isNot(contains(id)));

      // And the original user's dismissal survives a session restore.
      SessionManager().setCurrentUser(staff);
      expect(await service.getDismissedBannerIds(), contains(id));
    });
  });

  group('AnnouncementBanner widget', () {
    /// sqflite_ffi futures do not complete inside the fake-async zone of
    /// testWidgets, so the widget tests run against an in-memory service.
    Future<void> pumpBanner(WidgetTester tester, List<Announcement> pinned,
        {Set<int>? dismissed}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            announcementServiceProvider.overrideWithValue(
              _FakeAnnouncementService(pinned, dismissed ?? {}),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AnnouncementBanner()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Announcement pinnedAnnouncement(int id, String title) => Announcement(
          id: id,
          title: title,
          content: 'Content for $title',
          isPinned: true,
          createdAt: DateTime(2026, 9, 15, 8, 30),
        );

    testWidgets('renders the pinned announcement title and content',
        (tester) async {
      await pumpBanner(tester, [pinnedAnnouncement(1, 'Fiesta closure')]);

      expect(find.text('Fiesta closure'), findsOneWidget);
      expect(find.text('Content for Fiesta closure'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('shows +N more chip when multiple pinned', (tester) async {
      await pumpBanner(tester, [
        pinnedAnnouncement(1, 'First'),
        pinnedAnnouncement(2, 'Second'),
      ]);

      expect(find.text('+1 more'), findsOneWidget);
    });

    testWidgets('dismiss button hides the banner and records the id',
        (tester) async {
      final service = _FakeAnnouncementService(
          [pinnedAnnouncement(7, 'Dismissable')], {});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            announcementServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AnnouncementBanner()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Dismissable'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('Dismissable'), findsNothing);
      expect(service.dismissedIds, contains(7));
    });

    testWidgets('hides announcements already dismissed by the user',
        (tester) async {
      await pumpBanner(
        tester,
        [pinnedAnnouncement(1, 'Old news')],
        dismissed: {1},
      );

      expect(find.text('Old news'), findsNothing);
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    });

    testWidgets('renders nothing when no pinned announcements',
        (tester) async {
      await pumpBanner(tester, const []);

      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    });
  });
}

/// In-memory [AnnouncementService] for widget tests — the real service
/// touches sqflite_ffi which cannot run inside testWidgets' fake zone.
class _FakeAnnouncementService extends AnnouncementService {
  _FakeAnnouncementService(this._pinned, this.dismissedIds);

  final List<Announcement> _pinned;
  final Set<int> dismissedIds;

  @override
  Future<List<Announcement>> getBannerAnnouncements() async => _pinned;

  @override
  Future<Set<int>> getDismissedBannerIds() async => dismissedIds;

  @override
  Future<void> dismissBannerAnnouncement(int announcementId) async {
    dismissedIds.add(announcementId);
  }
}
