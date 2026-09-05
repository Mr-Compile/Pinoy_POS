import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/session_metadata.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/secure_storage_service.dart';

/// Tests for the session metadata, timeout, and restore flow.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();
    final seeder = DatabaseSeeder();
    await seeder.seed();
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
  });

  test('login creates persisted session metadata with an 8-hour expiry', () async {
    final auth = AuthService();
    final result = await auth.login('owner', 'owner123');
    expect(result, LoginResult.success);

    final metadata = auth.currentSessionMetadata;
    expect(metadata, isNotNull);
    expect(metadata!.userId, 1);
    expect(metadata.pinVerified, isTrue);
    expect(metadata.lastActivityAt.isBefore(DateTime.now()), isTrue);

    final hardLimit = DateTime.now().add(const Duration(hours: 8));
    expect(
      metadata.sessionExpiresAt.isBefore(hardLimit.add(const Duration(seconds: 5))) &&
          metadata.sessionExpiresAt.isAfter(hardLimit.subtract(const Duration(seconds: 5))),
      isTrue,
    );
  });

  test('restoreSession returns active for a valid session', () async {
    final auth = AuthService();
    await auth.login('owner', 'owner123');

    final auth2 = AuthService();
    final status = await auth2.restoreSession();
    expect(status, SessionStatus.active);
    expect(auth2.currentUser, isNotNull);
  });

  test('restoreSession returns locked when inactivity expired and user has PIN', () async {
    final auth = AuthService();
    await auth.login('owner', 'owner123');
    await auth.updateProfile(
      userId: auth.currentUser!.id!,
      fullName: auth.currentUser!.fullName,
      pin: '1234',
    );
    await auth.setPinVerified(false);

    final stale = DateTime.now().subtract(const Duration(minutes: 30));
    await auth.touchSession(stale);

    final auth2 = AuthService();
    final status = await auth2.restoreSession();
    expect(status, SessionStatus.locked);
    expect(auth2.currentUser, isNotNull);
  });

  test('restoreSession returns expired when inactivity expired and user has no PIN', () async {
    final auth = AuthService();
    await auth.login('staff', 'staff123');

    final stale = DateTime.now().subtract(const Duration(minutes: 30));
    await auth.touchSession(stale);

    final auth2 = AuthService();
    final status = await auth2.restoreSession();
    expect(status, SessionStatus.expired);
    expect(auth2.currentUser, isNull);
  });

  test('restoreSession returns expired when the 8-hour hard limit has passed', () async {
    final auth = AuthService();
    await auth.login('owner', 'owner123');

    final original = auth.currentSessionMetadata!;
    final expired = SessionMetadata(
      userId: original.userId,
      sessionExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      lastActivityAt: DateTime.now().subtract(const Duration(minutes: 1)),
      pinVerified: original.pinVerified,
    );
    await SecureStorageService().write(
      key: 'session_token',
      value: jsonEncode(expired.toMap()),
    );

    final auth2 = AuthService();
    final status = await auth2.restoreSession();
    expect(status, SessionStatus.expired);
    expect(auth2.currentUser, isNull);
  });

  test('logout clears the persisted session metadata and user id', () async {
    final auth = AuthService();
    await auth.login('owner', 'owner123');
    await auth.logout();

    final auth2 = AuthService();
    final status = await auth2.restoreSession();
    expect(status, SessionStatus.none);
    expect(auth2.currentUser, isNull);
    expect(auth2.currentSessionMetadata, isNull);
  });
}
