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

class _FakeTrashService extends TrashService {
  final List<TrashItem> _items;

  _FakeTrashService(this._items);

  @override
  Future<List<TrashItem>> getAllTrash() async => _items;

  @override
  Future<int> backfillSoftDeletedToTrash() async => 0;

  @override
  Future<int> processExpiredTrash() async => 0;

  @override
  Future<TrashOperationResult> restoreFromTrash(int id) async =>
      const TrashOperationResult(success: true);

  @override
  Future<TrashOperationResult> permanentDelete(int id) async =>
      const TrashOperationResult(success: true);

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
      deletedBy: 1,
      deletedByName: 'Owner',
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
      deletedBy: 1,
      deletedByName: 'Owner',
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

  testWidgets('unified trash screen shows all entity types in one list',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService(owner)),
          trashServiceProvider.overrideWithValue(_FakeTrashService(trashItems)),
          notificationCountProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const TrashScreen(),
        ),
      ),
    );

    // Give the screen a tall viewport so the full unified list is built.
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    // Wait for the screen to load the fake trash list.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // There should be no TabBar or TabBarView.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);

    // All five entity types should be visible in the same list.
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Staff One'), findsOneWidget);
    expect(find.text('Merchant QR'), findsOneWidget);
    expect(find.text('Sale Day'), findsOneWidget);

    // Restore and delete action buttons are visible for the owner.
    expect(find.widgetWithIcon(IconButton, Icons.restore), findsWidgets);
    expect(find.widgetWithIcon(IconButton, Icons.delete_forever), findsWidgets);
  });

  testWidgets('filter dropdown filters the unified list without tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService(owner)),
          trashServiceProvider.overrideWithValue(_FakeTrashService(trashItems)),
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

    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);

    // Open the filter dropdown.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump(const Duration(milliseconds: 300));

    // Select "Products".
    await tester.tap(find.text('Products').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Only the product remains visible; the others are filtered out.
    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    expect(find.text('Staff One'), findsNothing);
    expect(find.text('Merchant QR'), findsNothing);
    expect(find.text('Sale Day'), findsNothing);

    // Still no tab UI.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
  });

  testWidgets('search filters the unified list across names and snapshot text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService(owner)),
          trashServiceProvider.overrideWithValue(_FakeTrashService(trashItems)),
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

    // Type a product name into the search field.
    await tester.enterText(find.byType(TextField).first, 'Canned');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Canned Tuna'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);

    // Clear and search for a snapshot value (announcement content).
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, '50% off');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sale Day'), findsOneWidget);
    expect(find.text('Canned Tuna'), findsNothing);
  });
}
