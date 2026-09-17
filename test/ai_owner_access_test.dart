import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/ai_capability_policy.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';

/// The owner can see everything in the system — business analytics,
/// staff accounts, per-staff sales, and system-administration data.
/// These tests pin the detection and policy rules that make queries
/// like "who are my staff" reach real database facts.
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

    await DatabaseSeeder().seed();

    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
  });

  final bi = BusinessIntelligenceService();

  Future<User> userByUsername(String username) async {
    final db = await DatabaseHelper().database;
    final maps =
        await db.query('users', where: 'username = ?', whereArgs: [username]);
    return User.fromMap(maps.single);
  }

  group('Owner staff & user intents', () {
    test('"who are my staff" resolves to the staff roster', () {
      final d = bi.detectIntent('who are my staff', role: UserRole.owner);
      expect(d.intent, BusinessIntent.userStatusSummary);
    });

    test('employee/team/user phrasings resolve to the staff roster', () {
      for (final q in [
        'list my employees',
        'show my team members',
        'list users',
        'who works here',
      ]) {
        final d = bi.detectIntent(q, role: UserRole.owner);
        expect(d.intent, BusinessIntent.userStatusSummary, reason: q);
      }
    });

    test('"how many staff" resolves to the user count summary', () {
      final d =
          bi.detectIntent('how many staff do i have', role: UserRole.owner);
      expect(d.intent, BusinessIntent.activeUserSummary);
    });

    test('"who is <name>" resolves to a user lookup', () {
      final d = bi.detectIntent('who is maria', role: UserRole.owner);
      expect(d.intent, BusinessIntent.userLookup);
    });

    test('staff sales questions resolve to per-staff performance', () {
      for (final q in [
        'staff sales today',
        'which staff sold the most this week',
        'my best employee',
        'sales per staff',
      ]) {
        final d = bi.detectIntent(q, role: UserRole.owner);
        expect(d.intent, BusinessIntent.staffSales, reason: q);
      }
    });

    test('staff questions do not swallow plain sales questions', () {
      final d = bi.detectIntent('how are my sales today',
          role: UserRole.owner);
      expect(d.intent, BusinessIntent.todaySales);
    });
  });

  group('Owner system-administration intents', () {
    test('backup, export, system status and activity are detected', () {
      expect(
        bi.detectIntent('when was the latest backup', role: UserRole.owner)
            .intent,
        BusinessIntent.backupSummary,
      );
      expect(
        bi.detectIntent('what was exported recently', role: UserRole.owner)
            .intent,
        BusinessIntent.exportSummary,
      );
      expect(
        bi.detectIntent('system status', role: UserRole.owner).intent,
        BusinessIntent.systemStatusSummary,
      );
      expect(
        bi.detectIntent('show recent activity', role: UserRole.owner)
            .intent,
        BusinessIntent.recentActivity,
      );
    });
  });

  group('Typo tolerance', () {
    test('misspelled sales questions still detect', () {
      for (final q in [
        'how are my saels today',
        'totla salse this wek',
        'sales yestrday',
      ]) {
        final d = bi.detectIntent(q, role: UserRole.owner);
        expect(
          [
            BusinessIntent.todaySales,
            BusinessIntent.yesterdaySales,
            BusinessIntent.weeklySales,
          ].contains(d.intent),
          isTrue,
          reason: '$q → ${d.intent}',
        );
      }
    });

    test('misspelled staff questions still detect', () {
      expect(
        bi.detectIntent('who are my staf', role: UserRole.owner).intent,
        BusinessIntent.userStatusSummary,
      );
      expect(
        bi.detectIntent('employe saels today', role: UserRole.owner)
            .intent,
        BusinessIntent.staffSales,
      );
      expect(
        bi.detectIntent('who is maira', role: UserRole.owner).intent,
        BusinessIntent.userLookup,
      );
      expect(
        bi.detectIntent("who's my staff", role: UserRole.owner).intent,
        BusinessIntent.userStatusSummary,
      );
    });

    test('misspelled system questions still detect', () {
      expect(
        bi.detectIntent('latest bakcup', role: UserRole.owner).intent,
        BusinessIntent.backupSummary,
      );
      expect(
        bi.detectIntent('recent activty', role: UserRole.owner).intent,
        BusinessIntent.recentActivity,
      );
    });

    test('misspelled product lookups still detect', () {
      expect(
        bi.detectIntent('prce of coke', role: UserRole.owner).intent,
        BusinessIntent.productLookup,
      );
      expect(
        bi.detectIntent('stok of lucky me', role: UserRole.owner).intent,
        BusinessIntent.productLookup,
      );
    });

    test('Taglish phrasing resolves to real intents', () {
      expect(
        bi.detectIntent('ilang staff ko', role: UserRole.owner).intent,
        BusinessIntent.activeUserSummary,
      );
      expect(
        bi.detectIntent('magkano ang coke', role: UserRole.owner).intent,
        BusinessIntent.productLookup,
      );
      expect(
        bi.detectIntent('kita ko today', role: UserRole.owner).intent,
        BusinessIntent.todaySales,
      );
    });
  });

  group('Owner capability policy', () {
    test('owner is allowed every data domain', () {
      for (final intent in [
        BusinessIntent.staffSales,
        BusinessIntent.userStatusSummary,
        BusinessIntent.activeUserSummary,
        BusinessIntent.userLookup,
        BusinessIntent.systemActivitySummary,
        BusinessIntent.recentActivity,
        BusinessIntent.backupSummary,
        BusinessIntent.exportSummary,
        BusinessIntent.systemStatusSummary,
        BusinessIntent.adminSummary,
      ]) {
        expect(AICapabilityPolicy.isAllowed(UserRole.owner, intent), isTrue,
            reason: intent.name);
      }
    });

    test('staff still cannot reach user data', () {
      expect(
        AICapabilityPolicy.isAllowed(
            UserRole.staff, BusinessIntent.userStatusSummary),
        isFalse,
      );
      expect(
        AICapabilityPolicy.isAllowed(UserRole.staff, BusinessIntent.userLookup),
        isFalse,
      );
      final d = bi.detectIntent('who are my staff', role: UserRole.staff);
      expect(d.intent, BusinessIntent.general);
    });
  });

  group('Owner facts', () {
    test('staffSales returns a per-staff performance block', () async {
      final staff = await userByUsername('staff');
      final db = await DatabaseHelper().database;
      await db.insert('sales', {
        'total_amount': 250.0,
        'cash_received': 250.0,
        'change': 0.0,
        'payment_method': 'Cash',
        'payment_status': 'confirmed',
        'user_id': staff.id,
        'created_at': DateTime.now().toIso8601String(),
        'receipt_number': '20260910-0001',
      });

      final facts = await bi.gatherFacts(
        DetectedIntent(intent: BusinessIntent.staffSales),
        role: UserRole.owner,
        userId: staff.id,
      );

      expect(facts.context, contains('STAFF SALES PERFORMANCE'));
      expect(facts.context, contains('Staff Member'));
      expect(facts.context, contains('250.00'));
      expect(facts.hasData, isTrue);
    });

    test('owner general context lists the team roster', () async {
      final owner = await userByUsername('owner');
      SessionManager().setCurrentUser(owner);

      final facts = await bi.gatherFacts(
        DetectedIntent(intent: BusinessIntent.general),
        role: UserRole.owner,
        userId: owner.id,
        query: 'hello',
      );

      expect(facts.context, contains('Team accounts'));
      expect(facts.context, contains('Staff Member'));
      expect(facts.context, contains('Store Owner'));
    });

    test('owner general context resolves a named staff member', () async {
      final owner = await userByUsername('owner');
      SessionManager().setCurrentUser(owner);

      final facts = await bi.gatherFacts(
        DetectedIntent(intent: BusinessIntent.general),
        role: UserRole.owner,
        userId: owner.id,
        query: 'tell me about staff member',
      );

      // The fallback resolves the mention against the users table and
      // returns the user-lookup facts rather than the thin context.
      expect(facts.context, contains('Staff Member'));
    });
  });
}
