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

  test('Owner has full AI permissions', () {
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
  });

  test('Admin has view and use AI advisor plus manage_ai_config', () {
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
    expect(SessionManager().hasPermission('view_pos'), isFalse);
    expect(SessionManager().hasPermission('view_reports'), isTrue);
    expect(SessionManager().hasPermission('view_staff_performance'), isTrue);
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
}
