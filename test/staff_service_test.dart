import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/staff_service.dart';

/// Integration tests for the owner StaffService.
///
/// Verifies CRUD, RBAC, search/filters, sales analytics, and activity-log
/// retrieval for staff management.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();

    final seeder = DatabaseSeeder();
    await seeder.seed();

    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 50));
  });

  Future<User> authenticateAsOwner() async {
    final repo = UserRepository();
    final owner = await repo.getByUsername('owner');
    if (owner == null) throw StateError('Seeded owner not found');
    SessionManager().setCurrentUser(owner);
    return owner;
  }

  Future<User> authenticateAsAdmin() async {
    final repo = UserRepository();
    final admin = await repo.getByUsername('admin');
    if (admin == null) throw StateError('Seeded admin not found');
    SessionManager().setCurrentUser(admin);
    return admin;
  }

  test('CREATE: owner can create a staff member', () async {
    await authenticateAsOwner();
    final staffService = StaffService();

    final result = await staffService.createStaff(
      username: 'newstaff',
      fullName: 'New Staff',
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.user, isNotNull);
    expect(result.user!.username, 'newstaff');
    expect(result.user!.role, UserRole.staff);
    expect(result.user!.mustChangePassword, isTrue);
  });

  test('RBAC: admin cannot create staff', () async {
    await authenticateAsAdmin();
    final staffService = StaffService();

    expect(
      () => staffService.createStaff(
        username: 'badstaff',
        fullName: 'Bad Staff',
      ),
      throwsA(isA<AuthorizationException>()),
    );
  });

  test('CREATE: duplicate username is rejected', () async {
    await authenticateAsOwner();
    final staffService = StaffService();

    await staffService.createStaff(
      username: 'dupstaff',
      fullName: 'Dup Staff',
    );

    final result = await staffService.createStaff(
      username: 'dupstaff',
      fullName: 'Dup Staff Two',
    );

    expect(result.success, isFalse);
  });

  test('CREATE: invalid PIN is rejected', () async {
    await authenticateAsOwner();
    final staffService = StaffService();

    final result = await staffService.createStaff(
      username: 'pinstaff',
      fullName: 'Pin Staff',
      pin: '12',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('PIN'));
  });

  test('READ: getStaff returns only staff', () async {
    await authenticateAsOwner();
    final staffService = StaffService();

    final staff = await staffService.getStaff();
    expect(staff.every((u) => u.role == UserRole.staff), isTrue);
    expect(staff.any((u) => u.username == 'staff'), isTrue);
    expect(staff.any((u) => u.username == 'owner'), isFalse);
    expect(staff.any((u) => u.username == 'admin'), isFalse);
  });

  test('READ: getStaff search filters by name and username', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    await staffService.createStaff(
      username: 'johndoe',
      fullName: 'John Doe',
    );

    var staff = await staffService.getStaff(search: 'john');
    expect(staff.length, 1);

    staff = await staffService.getStaff(search: 'johndoe');
    expect(staff.length, 1);

    staff = await staffService.getStaff(search: 'nomatch');
    expect(staff, isEmpty);
  });

  test('READ: getStaff filter by active status', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'togglestaff',
      fullName: 'Toggle Staff',
    );
    expect(created.success, isTrue);
    final staffId = created.user!.id!;

    await staffService.deactivateStaff(staffId);

    final active = await staffService.getStaff(activeOnly: true);
    expect(active.any((u) => u.id == staffId), isFalse);

    final inactive = await staffService.getStaff(activeOnly: false);
    expect(inactive.any((u) => u.id == staffId), isTrue);
  });

  test('READ: getStaffById returns staff only', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final owner = await UserRepository().getByUsername('owner');
    final admin = await UserRepository().getByUsername('admin');

    expect(await staffService.getStaffById(owner!.id!), isNull);
    expect(await staffService.getStaffById(admin!.id!), isNull);
  });

  test('UPDATE: owner can update staff details', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'updatestaff',
      fullName: 'Update Staff',
    );
    final staffId = created.user!.id!;

    final result = await staffService.updateStaff(
      staffId: staffId,
      username: 'updatedstaff',
      fullName: 'Updated Staff',
    );

    expect(result.success, isTrue);
    expect(result.user!.username, 'updatedstaff');
    expect(result.user!.fullName, 'Updated Staff');
  });

  test('UPDATE: changing username to existing is rejected', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'first',
      fullName: 'First Staff',
    );
    final staffId = created.user!.id!;
    await staffService.createStaff(
      username: 'second',
      fullName: 'Second Staff',
    );

    final result = await staffService.updateStaff(
      staffId: staffId,
      username: 'second',
    );

    expect(result.success, isFalse);
  });

  test('UPDATE: non-staff user cannot be updated via StaffService', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final admin = await UserRepository().getByUsername('admin');

    final result = await staffService.updateStaff(
      staffId: admin!.id!,
      username: 'newadminname',
    );

    expect(result.success, isFalse);
  });

  test('PASSWORD: owner can reset staff password', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'resetstaff',
      fullName: 'Reset Staff',
    );

    final result = await staffService.resetStaffPassword(created.user!.id!);

    expect(result.success, isTrue);
  });

  test('ACTIVATE/DEACTIVATE: owner can toggle staff status', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'togglestaff2',
      fullName: 'Toggle Staff Two',
    );
    final staffId = created.user!.id!;

    var staff = await staffService.getStaffById(staffId);
    expect(staff!.isActive, isTrue);

    await staffService.deactivateStaff(staffId);
    staff = await staffService.getStaffById(staffId);
    expect(staff!.isActive, isFalse);

    await staffService.activateStaff(staffId);
    staff = await staffService.getStaffById(staffId);
    expect(staff!.isActive, isTrue);
  });

  test('DELETE: owner can soft-delete and restore staff', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'deletestaff',
      fullName: 'Delete Staff',
    );
    final staffId = created.user!.id!;

    var softDelete = await staffService.softDeleteStaff(staffId);
    expect(softDelete.success, isTrue);

    var staff = await staffService.getStaffById(staffId);
    expect(staff, isNull);

    var deleted = await staffService.getDeletedStaff();
    expect(deleted.any((u) => u.id == staffId), isTrue);

    var restore = await staffService.restoreStaff(staffId);
    expect(restore.success, isTrue);

    staff = await staffService.getStaffById(staffId);
    expect(staff, isNotNull);
  });

  test('DELETE: permanent delete requires soft-delete first', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'permstaff',
      fullName: 'Perm Staff',
    );
    final staffId = created.user!.id!;

    var permanent = await staffService.permanentlyDeleteStaff(staffId);
    expect(permanent.success, isFalse);

    await staffService.softDeleteStaff(staffId);
    permanent = await staffService.permanentlyDeleteStaff(staffId);
    expect(permanent.success, isTrue);

    final staff = await staffService.getStaffById(staffId);
    expect(staff, isNull);
  });

  test('SALES ANALYTICS: returns empty analytics when no sales', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final seededStaff = await UserRepository().getByUsername('staff');
    final staffId = seededStaff!.id!;

    final analytics = await staffService.getStaffSalesAnalytics(
      staffId,
      ReportingPeriod.thisMonth,
    );

    expect(analytics.totalSales, 0.0);
    expect(analytics.transactionCount, 0);
  });

  test('ACTIVITY LOGS: returns staff activity logs', () async {
    await authenticateAsOwner();
    final staffService = StaffService();
    final created = await staffService.createStaff(
      username: 'logstaff',
      fullName: 'Log Staff',
    );
    final staffId = created.user!.id!;

    final logs = await staffService.getStaffActivityLogs(staffId);
    expect(logs, isNotEmpty);
    expect(logs.any((l) => l.action == 'STAFF_CREATED'), isTrue);
  });
}
