import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/core/trash_operation_result.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/notification_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService extends AuthService {
  final User _owner;

  _FakeAuthService(this._owner);

  @override
  User? get currentUser => _owner;

  @override
  bool get isAuthenticated => true;

  @override
  Future<SessionStatus> restoreSession() async => SessionStatus.active;

  @override
  bool hasPermission(String permission) => true;
}

class _LimitedFakeAuthService extends _FakeAuthService {
  final Set<String> _permissions;

  _LimitedFakeAuthService(super._owner, this._permissions);

  @override
  bool hasPermission(String permission) => _permissions.contains(permission);
}

class _FakeTrashService extends TrashService {
  final List<TrashItem> _sourceItems;
  final Set<int> _removedIds = {};

  int? _lastRestoredId;
  int? _lastPermanentlyDeletedId;

  _FakeTrashService(this._sourceItems);

  Set<int> get removedIds => _removedIds;
  int? get lastRestoredId => _lastRestoredId;
  int? get lastPermanentlyDeletedId => _lastPermanentlyDeletedId;

  @override
  Future<List<TrashItem>> getAllTrash() async =>
      _sourceItems.where((i) => i.id != null && !_removedIds.contains(i.id!)).toList();

  @override
  Future<int> backfillSoftDeletedToTrash() async => 0;

  @override
  Future<int> processExpiredTrash() async => 0;

  @override
  Future<TrashOperationResult> restoreFromTrash(int id) async {
    _lastRestoredId = id;
    _removedIds.add(id);
    return const TrashOperationResult(success: true);
  }

  @override
  Future<TrashOperationResult> permanentDelete(int id) async {
    _lastPermanentlyDeletedId = id;
    _removedIds.add(id);
    return const TrashOperationResult(success: true);
  }

  @override
  Future<TrashOperationResult> bulkRestore(List<int> ids) async =>
      const TrashOperationResult(success: true);

  @override
  Future<TrashOperationResult> bulkPermanentDelete(List<int> ids) async =>
      const TrashOperationResult(success: true);
}

TrashItem _trashItemForProduct(Product product) => TrashItem(
      id: 1,
      entityType: 'product',
      entityId: product.id!,
      entityName: product.name,
      snapshotJson: TrashService.snapshotForProduct(product),
      deletedBy: 1,
      deletedByName: 'Owner',
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

TrashItem _trashItemForCategory(Category category) => TrashItem(
      id: 2,
      entityType: 'category',
      entityId: category.id!,
      entityName: category.name,
      snapshotJson: TrashService.snapshotForCategory(category),
      deletedBy: 2,
      deletedByName: 'Admin',
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

TrashItem _trashItemForUser(User user) => TrashItem(
      id: 3,
      entityType: 'user',
      entityId: user.id!,
      entityName: user.fullName,
      snapshotJson: TrashService.snapshotForUser(user),
      deletedBy: 1,
      deletedByName: 'Owner',
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

TrashItem _trashItemForQr() => TrashItem(
      id: 4,
      entityType: 'merchant_qr',
      entityId: 0,
      entityName: 'Merchant QR',
      snapshotJson: '{"path":"gcash_qr/test.png","type":"image/png"}',
      deletedBy: 1,
      deletedByName: 'Owner',
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

TrashItem _trashItemForAnnouncement(Announcement announcement) => TrashItem(
      id: 5,
      entityType: 'announcement',
      entityId: announcement.id!,
      entityName: announcement.title,
      snapshotJson: TrashService.snapshotForAnnouncement(announcement),
      deletedBy: 2,
      deletedByName: 'Admin',
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

void main() {
  final now = DateTime.now();

  final owner = User(
    id: 1,
    username: 'owner',
    passwordHash: '',
    role: UserRole.owner,
    fullName: 'Owner User',
    createdAt: now,
    isActive: true,
    mustChangePassword: false,
  );

  final product = Product(
    id: 1,
    name: 'Canned Tuna',
    price: 55.0,
    stock: 20,
    createdAt: now,
    deletedAt: now,
  );

  final category = Category(
    id: 1,
    name: 'Groceries',
    description: 'Food items',
    createdAt: now,
    deletedAt: now,
  );

  final user = User(
    id: 2,
    username: 'staff1',
    passwordHash: '',
    role: UserRole.staff,
    fullName: 'Staff One',
    createdAt: now,
    isActive: true,
    deletedAt: now,
  );

  final announcement = Announcement(
    id: 1,
    title: 'Sale Day',
    content: 'Everything 50% off',
    createdAt: now,
    deletedAt: now,
  );

  final trashItems = [
    _trashItemForProduct(product),
    _trashItemForCategory(category),
    _trashItemForUser(user),
    _trashItemForQr(),
    _trashItemForAnnouncement(announcement),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SessionManager().setCurrentUser(owner);
  });

  Future<void> pumpTrashScreen(
    WidgetTester tester, {
    AuthService? authService,
    TrashService? trashService,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService ?? _FakeAuthService(owner)),
          trashServiceProvider.overrideWithValue(trashService ?? _FakeTrashService(trashItems)),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const TrashScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('unified trash screen shows all records in one list with no filters',
      (WidgetTester tester) async {
    await pumpTrashScreen(tester);

    // No tab or dropdown filtering UI should exist.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);

    // A single search field should be present.
    expect(find.byType(AppSearchField), findsOneWidget);

    // All five entity types should appear in the same list.
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Staff One'), findsOneWidget);
    expect(find.text('Merchant QR'), findsOneWidget);
    expect(find.text('Sale Day'), findsOneWidget);

    // Restore and delete action buttons are visible for the owner.
    expect(find.widgetWithIcon(IconButton, Icons.restore), findsWidgets);
    expect(find.widgetWithIcon(IconButton, Icons.delete_forever), findsWidgets);
  });

  testWidgets('search filters the unified list and clear restores all records',
      (WidgetTester tester) async {
    await pumpTrashScreen(tester);

    // Search by product name.
    await tester.enterText(find.byType(TextField).first, 'Canned');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);

    // Clear search.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Staff One'), findsOneWidget);

    // Search by username in a user snapshot.
    await tester.enterText(find.byType(TextField).first, 'staff1');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Staff One'), findsOneWidget);
    expect(find.text('Canned Tuna'), findsNothing);

    // Clear.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    // Search by record type label.
    await tester.enterText(find.byType(TextField).first, 'qr');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Merchant QR'), findsOneWidget);
    expect(find.text('Canned Tuna'), findsNothing);

    // Clear.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    // Search by snapshot content (announcement body).
    await tester.enterText(find.byType(TextField).first, '50% off');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sale Day'), findsOneWidget);
    expect(find.text('Canned Tuna'), findsNothing);
  });

  testWidgets('empty trash shows "Trash is empty."', (WidgetTester tester) async {
    await pumpTrashScreen(
      tester,
      trashService: _FakeTrashService([]),
    );

    expect(find.text('Trash is empty.'), findsOneWidget);
  });

  testWidgets('search with no matches shows "No matching records found."',
      (WidgetTester tester) async {
    await pumpTrashScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'nonexistent');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No matching records found.'), findsOneWidget);
  });

  testWidgets('restore from search results restores the correct record',
      (WidgetTester tester) async {
    final fakeService = _FakeTrashService(trashItems);
    await pumpTrashScreen(tester, trashService: fakeService);

    await tester.enterText(find.byType(TextField).first, 'Canned');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Canned Tuna'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.restore));
    await tester.pump(const Duration(milliseconds: 300));

    // Confirm the restore dialog.
    expect(find.text('Restore from Trash?'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Restore'));
    await tester.pump(const Duration(milliseconds: 300));

    // Dismiss the success dialog.
    expect(find.text('Restored'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(fakeService.lastRestoredId, 1);
    expect(find.text('Canned Tuna'), findsNothing);
    expect(find.text('No matching records found.'), findsOneWidget);
  });

  testWidgets('permanent delete from search results deletes the correct record',
      (WidgetTester tester) async {
    final fakeService = _FakeTrashService(trashItems);
    await pumpTrashScreen(tester, trashService: fakeService);

    await tester.enterText(find.byType(TextField).first, 'Canned');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Canned Tuna'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_forever));
    await tester.pump(const Duration(milliseconds: 300));

    // Confirm the permanent delete dialog.
    expect(find.text('Permanently Delete?'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Delete Permanently'));
    await tester.pump(const Duration(milliseconds: 300));

    // Dismiss the success dialog.
    expect(find.text('Deleted'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(fakeService.lastPermanentlyDeletedId, 1);
    expect(find.text('Canned Tuna'), findsNothing);
    expect(find.text('No matching records found.'), findsOneWidget);
  });

  testWidgets('permissions still filter the unified list to authorized types',
      (WidgetTester tester) async {
    final limitedAuth = _LimitedFakeAuthService(
      owner,
      {
        'view_trash',
        'view_products',
        'view_categories',
      },
    );

    await pumpTrashScreen(
      tester,
      authService: limitedAuth,
    );

    // Allowed records are visible.
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);

    // Unauthorized entity types are not shown.
    expect(find.text('Staff One'), findsNothing);
    expect(find.text('Merchant QR'), findsNothing);
    expect(find.text('Sale Day'), findsNothing);
  });
}
