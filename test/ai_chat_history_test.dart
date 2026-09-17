import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/phone_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/dao/ai_chat_message_dao.dart';
import 'package:pinoy_pos/data/models/ai_chat_message.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_chat_history_service.dart';

/// Tests for persisted AI advisor conversations and the settings-side
/// changes that shipped with them (merchant identity + phone hint).
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

    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
  });

  Future<User> userByUsername(String username) async {
    final db = await DatabaseHelper().database;
    final maps =
        await db.query('users', where: 'username = ?', whereArgs: [username]);
    return User.fromMap(maps.single);
  }

  AIChatMessage makeMsg(
    String text, {
    bool isUser = false,
    AIResponse? response,
    List<String> followUps = const [],
  }) =>
      AIChatMessage(
        text: text,
        isUser: isUser,
        response: response,
        followUps: followUps,
        timestamp: DateTime.now(),
      );

  // ── AIResponse serialization ───────────────────────────────────────────

  group('AIResponse JSON', () {
    test('round-trips message, instructions, actions and suggestions', () {
      const original = AIResponse(
        message: 'Go to Products.',
        instructions: [
          AIInstruction(text: 'Open the Products page.'),
          AIInstruction(
            text: 'Tap Add Product.',
            action: AIAction(
              type: AIActionType.navigate,
              destination: 'products',
              label: 'Open Products',
              parameters: {'highlight': 'add'},
            ),
          ),
        ],
        actions: [
          AIAction(
            type: AIActionType.navigate,
            destination: 'products',
            label: 'Open Products',
          ),
        ],
        suggestions: ['Show my sales today'],
      );

      final restored = AIResponse.fromJson(original.toJson());

      expect(restored.message, original.message);
      expect(restored.instructions.length, 2);
      expect(restored.instructions[1].action?.destination, 'products');
      expect(
        restored.instructions[1].action?.parameters,
        {'highlight': 'add'},
      );
      expect(restored.actions.single.label, 'Open Products');
      expect(restored.suggestions, ['Show my sales today']);
    });

    test('skips malformed entries instead of throwing', () {
      final restored = AIResponse.fromJson({
        'message': 'ok',
        'instructions': [
          {'text': 'valid step'},
          {'action': 'not-a-map'},
          42,
        ],
        'actions': [
          {'type': 'navigate', 'destination': 'sales', 'label': 'Sales'},
          {'type': 'not_a_real_type', 'destination': 'x', 'label': 'X'},
          {'type': 'navigate'}, // missing destination/label
          'garbage',
        ],
        'suggestions': ['one', 5, null],
      });

      expect(restored.instructions.single.text, 'valid step');
      expect(restored.actions.single.destination, 'sales');
      expect(restored.suggestions, ['one', '5']);
    });

    test('handles a completely empty or wrong-shaped map', () {
      final empty = AIResponse.fromJson(const {});
      expect(empty.message, '');
      expect(empty.isPlainMessage, isTrue);
    });
  });

  // ── AIChatMessage row serialization ────────────────────────────────────

  group('AIChatMessage rows', () {
    test('toRow/fromRow round-trips all fields', () {
      final ts = DateTime(2026, 3, 1, 10, 30);
      final message = AIChatMessage(
        text: 'hello',
        isUser: false,
        isError: true,
        timestamp: ts,
        response: const AIResponse(
          message: 'hello',
          suggestions: ['next'],
        ),
        followUps: const ['a', 'b'],
      );

      final row = message.toRow(7);
      expect(row['user_id'], 7);
      expect(row['is_user'], 0);
      expect(row['is_error'], 1);
      expect(row['response_json'], isA<String>());
      expect(row['follow_ups_json'], isA<String>());

      final restored = AIChatMessage.fromRow(row);
      expect(restored.text, 'hello');
      expect(restored.isUser, isFalse);
      expect(restored.isError, isTrue);
      expect(restored.timestamp, ts);
      expect(restored.response?.suggestions, ['next']);
      expect(restored.followUps, ['a', 'b']);
    });

    test('fromRow tolerates malformed JSON blobs', () {
      final restored = AIChatMessage.fromRow({
        'user_id': 1,
        'is_user': 0,
        'text': 'kept text',
        'is_error': 0,
        'response_json': '{not valid json',
        'follow_ups_json': '[unclosed',
        'created_at': 'also-not-a-date',
      });

      expect(restored.text, 'kept text');
      expect(restored.response, isNull);
      expect(restored.followUps, isEmpty);
    });
  });

  // ── DAO persistence ────────────────────────────────────────────────────

  group('AIChatMessageDao', () {
    test('ai_chat_messages table exists with expected columns', () async {
      final db = await DatabaseHelper().database;
      final columns =
          await db.rawQuery('PRAGMA table_info(ai_chat_messages)');
      final names = columns.map((c) => c['name'] as String).toSet();

      expect(
        names,
        containsAll([
          'id',
          'user_id',
          'is_user',
          'text',
          'is_error',
          'response_json',
          'follow_ups_json',
          'created_at',
        ]),
      );
    });

    test('persists messages and returns them oldest to newest', () async {
      final owner = await userByUsername('owner');
      final dao = AIChatMessageDao();

      await dao.insertForUser(owner.id!, makeMsg('first', isUser: true));
      await dao.insertForUser(owner.id!, makeMsg('second'));
      await dao.insertForUser(owner.id!, makeMsg('third', isUser: true));

      final loaded = await dao.getRecentForUser(owner.id!);
      expect(loaded.map((m) => m.text), ['first', 'second', 'third']);
    });

    test('restores structured responses from persisted JSON', () async {
      final owner = await userByUsername('owner');
      final dao = AIChatMessageDao();

      await dao.insertForUser(
        owner.id!,
        makeMsg(
          'Here is how.',
          response: const AIResponse(
            message: 'Here is how.',
            instructions: [AIInstruction(text: 'Tap Sales.')],
            actions: [
              AIAction(
                type: AIActionType.navigate,
                destination: 'sales',
                label: 'Open Sales',
              ),
            ],
          ),
        ),
      );

      final loaded = await dao.getRecentForUser(owner.id!);
      final restored = loaded.single.response;
      expect(restored, isNotNull);
      expect(restored!.instructions.single.text, 'Tap Sales.');
      expect(restored.actions.single.destination, 'sales');
    });

    test('conversations are isolated per user', () async {
      final owner = await userByUsername('owner');
      final staff = await userByUsername('staff');
      final dao = AIChatMessageDao();

      await dao.insertForUser(owner.id!, makeMsg('owner only'));
      await dao.insertForUser(staff.id!, makeMsg('staff only'));

      final ownerConv = await dao.getRecentForUser(owner.id!);
      final staffConv = await dao.getRecentForUser(staff.id!);

      expect(ownerConv.single.text, 'owner only');
      expect(staffConv.single.text, 'staff only');
    });

    test('deleteForUser removes only that user\'s conversation', () async {
      final owner = await userByUsername('owner');
      final staff = await userByUsername('staff');
      final dao = AIChatMessageDao();

      await dao.insertForUser(owner.id!, makeMsg('keep me'));
      await dao.insertForUser(staff.id!, makeMsg('delete me'));

      await dao.deleteForUser(staff.id!);

      expect(await dao.getRecentForUser(staff.id!), isEmpty);
      expect((await dao.getRecentForUser(owner.id!)).single.text, 'keep me');
    });

    test('pruneForUser keeps only the newest messages', () async {
      final owner = await userByUsername('owner');
      final dao = AIChatMessageDao();

      for (var i = 0; i < 5; i++) {
        await dao.insertForUser(owner.id!, makeMsg('msg $i'));
      }
      await dao.pruneForUser(owner.id!, keep: 2);

      final loaded = await dao.getRecentForUser(owner.id!);
      expect(loaded.map((m) => m.text), ['msg 3', 'msg 4']);
    });
  });

  // ── History service (session-scoped) ───────────────────────────────────

  group('AIChatHistoryService', () {
    test('loadConversation returns the current user\'s stored messages',
        () async {
      final owner = await userByUsername('owner');
      SessionManager().setCurrentUser(owner);

      final service = AIChatHistoryService();
      expect(await service.loadConversation(), isEmpty);

      await service.appendMessage(makeMsg('hi', isUser: true));
      await service.appendMessage(makeMsg('reply'));

      final convo = await service.loadConversation();
      expect(convo.map((m) => m.text), ['hi', 'reply']);
    });

    test('a different account sees its own conversation, not the previous '
        'one', () async {
      final owner = await userByUsername('owner');
      final staff = await userByUsername('staff');
      final service = AIChatHistoryService();

      SessionManager().setCurrentUser(owner);
      await service.appendMessage(makeMsg('owner message'));

      SessionManager().setCurrentUser(staff);
      expect(await service.loadConversation(), isEmpty);

      await service.appendMessage(makeMsg('staff message'));
      expect(
        (await service.loadConversation()).single.text,
        'staff message',
      );

      SessionManager().setCurrentUser(owner);
      expect(
        (await service.loadConversation()).single.text,
        'owner message',
      );
    });

    test('clearConversation removes only the current user\'s history',
        () async {
      final owner = await userByUsername('owner');
      final staff = await userByUsername('staff');
      final service = AIChatHistoryService();

      SessionManager().setCurrentUser(owner);
      await service.appendMessage(makeMsg('owner convo'));
      SessionManager().setCurrentUser(staff);
      await service.appendMessage(makeMsg('staff convo'));

      await service.clearConversation();
      expect(await service.loadConversation(), isEmpty);

      SessionManager().setCurrentUser(owner);
      expect(
        (await service.loadConversation()).single.text,
        'owner convo',
      );
    });

    test('returns nothing and writes nothing when no one is logged in',
        () async {
      final service = AIChatHistoryService();
      await service.appendMessage(makeMsg('orphan'));
      expect(await service.loadConversation(), isEmpty);

      final db = await DatabaseHelper().database;
      expect(await db.query('ai_chat_messages'), isEmpty);
    });

    test('restored messages drop stale create-product confirmation actions',
        () async {
      final owner = await userByUsername('owner');
      SessionManager().setCurrentUser(owner);

      final service = AIChatHistoryService();
      await service.appendMessage(
        makeMsg(
          'Confirm to create the product.',
          response: const AIResponse(
            message: 'Confirm to create the product.',
            actions: [
              AIAction(
                type: AIActionType.createProduct,
                destination: 'products',
                label: 'Create Product',
              ),
              AIAction(
                type: AIActionType.navigate,
                destination: 'products',
                label: 'Open Products',
              ),
            ],
          ),
        ),
      );

      final convo = await service.loadConversation();
      final restored = convo.single.response!;
      // The one-shot create action is stripped; navigation survives.
      expect(restored.actions.single.type, AIActionType.navigate);
    });
  });

  // ── Merchant identity separation ───────────────────────────────────────

  group('Merchant identity separation', () {
    test('PaymentSettings maps only the dedicated merchant fields', () {
      final settings = Settings(
        storeName: 'My Sari-Sari Store',
        storePhone: '0917 111 2222',
        gcashMerchantName: 'GCash Payee Co',
        gcashMerchantPhone: '0918 333 4444',
        gcashEnabled: true,
        gcashReferenceRequired: true,
        gcashCustomerNameRequirement: 'optional',
        gcashPaymentProofRequirement: 'optional',
        gcashVerificationMode: 'immediate',
        gcashReferenceMinLength: 13,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final payment = PaymentSettings.fromSettings(settings);
      expect(payment.gcashMerchantName, 'GCash Payee Co');
      expect(payment.gcashMerchantPhone, '0918 333 4444');
    });

    test('Settings map round-trips store and merchant fields separately',
        () {
      final settings = Settings(
        storeName: 'Store Name',
        storePhone: '0917 000 0000',
        gcashMerchantName: 'Merchant Name',
        gcashMerchantPhone: '0918 000 0000',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final restored = Settings.fromMap(settings.toMap());
      expect(restored.storeName, 'Store Name');
      expect(restored.storePhone, '0917 000 0000');
      expect(restored.gcashMerchantName, 'Merchant Name');
      expect(restored.gcashMerchantPhone, '0918 000 0000');
    });

    test('copyWith keeps the two identities independent', () {
      final base = Settings(
        storeName: 'Store A',
        storePhone: '0917 111 1111',
        gcashMerchantName: 'Merchant A',
        gcashMerchantPhone: '0918 222 2222',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      // Changing store fields must not touch merchant fields and vice versa.
      final storeEdit = base.copyWith(storeName: 'Store B');
      expect(storeEdit.gcashMerchantName, 'Merchant A');
      final merchantEdit = base.copyWith(gcashMerchantName: 'Merchant B');
      expect(merchantEdit.storeName, 'Store A');
    });

    test('settings table carries the dedicated merchant columns', () async {
      final db = await DatabaseHelper().database;
      final columns = await db.rawQuery('PRAGMA table_info(settings)');
      final names = columns.map((c) => c['name'] as String).toSet();

      expect(names, containsAll(['gcash_merchant_name', 'gcash_merchant_phone']));
      expect(names, containsAll(['store_name', 'store_phone']));
    });
  });

  // ── Phone placeholder ──────────────────────────────────────────────────

  group('Phone placeholder', () {
    test('phMobileHint is a masked placeholder, not a real-looking number',
        () {
      expect(PhoneUtils.phMobileHint, '09XX XXX XXXX');
      // It must not normalize into a usable number.
      expect(PhoneUtils.isValidPhMobile(PhoneUtils.phMobileHint), isFalse);
    });
  });
}
