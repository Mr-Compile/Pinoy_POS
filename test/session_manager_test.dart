import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';

/// Unit tests for role-based permissions, specifically the AI-related
/// permissions introduced by the repair phase.
void main() {
  setUp(() {
    SessionManager.resetForTest();
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  test('Owner has full AI permissions but no system management', () {
    SessionManager().setCurrentUser(User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));

    expect(SessionManager().hasPermission('view_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('use_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('manage_ai_config'), isFalse);
    expect(SessionManager().hasPermission('manage_ai_quota'), isFalse);
    expect(SessionManager().hasPermission('backup_restore'), isFalse);
  });

  test('Admin has AI and system management permissions', () {
    SessionManager().setCurrentUser(User(
      username: 'admin',
      passwordHash: '',
      fullName: 'Admin',
      role: UserRole.admin,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));

    expect(SessionManager().hasPermission('view_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('use_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('manage_ai_config'), isTrue);
    expect(SessionManager().hasPermission('manage_ai_quota'), isTrue);
    expect(SessionManager().hasPermission('backup_restore'), isTrue);
    expect(SessionManager().hasPermission('view_pos'), isFalse);
    expect(SessionManager().hasPermission('view_reports'), isFalse);
    expect(SessionManager().hasPermission('view_staff_performance'), isFalse);
  });

  test('Only Admin can manage global session settings', () {
    SessionManager().setCurrentUser(User(
      username: 'admin',
      passwordHash: '',
      fullName: 'Admin',
      role: UserRole.admin,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('manage_session_settings'), isTrue);

    SessionManager().setCurrentUser(User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('manage_session_settings'), isFalse);

    SessionManager().setCurrentUser(User(
      username: 'staff',
      passwordHash: '',
      fullName: 'Staff',
      role: UserRole.staff,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('manage_session_settings'), isFalse);
  });

  test('Admin cannot verify payments; Owner can', () {
    SessionManager().setCurrentUser(User(
      username: 'admin',
      passwordHash: '',
      fullName: 'Admin',
      role: UserRole.admin,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('verify_payments'), isFalse);

    SessionManager().setCurrentUser(User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('verify_payments'), isTrue);
  });

  test('Locked session denies all permissions until unlocked', () {
    SessionManager().setCurrentUser(User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));

    expect(SessionManager().hasPermission('view_settings'), isTrue);
    expect(SessionManager().isSessionLocked, isFalse);

    // PIN lock: user record stays for the unlock flow, but permission
    // checks must fail so background services cannot act while locked.
    SessionManager().setSessionLocked(true);
    expect(SessionManager().currentUser, isNotNull);
    expect(SessionManager().isSessionLocked, isTrue);
    expect(SessionManager().hasPermission('view_settings'), isFalse);
    expect(SessionManager().hasPermission('create_sales'), isFalse);
    expect(SessionManager().canEditBusinessSettings(), isFalse);

    SessionManager().setSessionLocked(false);
    expect(SessionManager().hasPermission('view_settings'), isTrue);
  });

  test('setCurrentUser and clearCurrentUser reset the lock flag', () {
    final owner = User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    );

    SessionManager().setCurrentUser(owner);
    SessionManager().setSessionLocked(true);

    // Successful PIN verify re-sets the user — session is unlocked again.
    SessionManager().setCurrentUser(owner);
    expect(SessionManager().isSessionLocked, isFalse);
    expect(SessionManager().hasPermission('view_settings'), isTrue);

    SessionManager().setSessionLocked(true);
    SessionManager().clearCurrentUser();
    expect(SessionManager().isSessionLocked, isFalse);
    expect(SessionManager().currentUser, isNull);
  });

  test('Staff has view and use AI advisor but not manage_ai_config', () {
    SessionManager().setCurrentUser(User(
      username: 'staff',
      passwordHash: '',
      fullName: 'Staff',
      role: UserRole.staff,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));

    expect(SessionManager().hasPermission('view_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('use_ai_advisor'), isTrue);
    expect(SessionManager().hasPermission('manage_ai_config'), isFalse);
    expect(SessionManager().hasPermission('view_pos'), isTrue);
    expect(SessionManager().hasPermission('view_reports'), isTrue);
  });

  test('Staff cannot change category status; Owner can', () {
    SessionManager().setCurrentUser(User(
      username: 'staff',
      passwordHash: '',
      fullName: 'Staff',
      role: UserRole.staff,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    // Read-only catalog access stays; the status mutation does not.
    expect(SessionManager().hasPermission('view_categories'), isTrue);
    expect(SessionManager().hasPermission('change_category_status'), isFalse);

    SessionManager().setCurrentUser(User(
      username: 'owner',
      passwordHash: '',
      fullName: 'Owner',
      role: UserRole.owner,
      mustChangePassword: false,
      isActive: true,
      createdAt: DateTime.now(),
    ));
    expect(SessionManager().hasPermission('change_category_status'), isTrue);
  });
}
