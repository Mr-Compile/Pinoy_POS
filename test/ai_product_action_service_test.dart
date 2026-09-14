import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_product_action_service.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';

/// End-to-end tests for the AI product-creation flow:
/// parse → validate → confirm → execute → database.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    await DatabaseHelper().recreateSchemaForTest();
    await DatabaseSeeder().seed();
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
    AIProductActionService.resetForTest();

    final result = await AuthService().login('owner', 'owner123');
    expect(result, LoginResult.success);

    await CategoryService().createCategory(
      Category(name: 'Meals', createdAt: DateTime.now()),
    );
  });

  tearDown(() async {
    AIProductActionService.resetForTest();
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    SessionManager.resetForTest();
  });

  bool hasPerm(String p) => SessionManager().hasPermission(p);

  void loginAsStaff() {
    SessionManager().setCurrentUser(User(
      id: 2,
      username: 'staff',
      passwordHash: '',
      role: UserRole.staff,
      fullName: 'Test Staff',
      createdAt: DateTime.now(),
    ));
  }

  group('resolveCommand', () {
    test('returns null for non-product queries', () async {
      expect(
        await AIProductActionService.resolveCommand(
          'how were my sales today',
          hasPermission: hasPerm,
        ),
        isNull,
      );
      expect(
        await AIProductActionService.resolveCommand(
          'show products',
          hasPermission: hasPerm,
        ),
        isNull,
      );
    });

    test('how-to returns the guided format card', () async {
      final r = await AIProductActionService.resolveCommand(
        'how do I add a product',
        hasPermission: hasPerm,
      );
      expect(r, isNotNull);
      expect(r!.instructions.any((i) => i.text.contains('name=')), isTrue);
      expect(r.actions.any((a) => a.destination == 'products'), isTrue);
      expect(r.suggestions, isNotEmpty);
    });

    test('bare intent returns the guide', () async {
      final r = await AIProductActionService.resolveCommand(
        'i want to create a product',
        hasPermission: hasPerm,
      );
      expect(r, isNotNull);
      expect(r!.instructions, isNotEmpty);
    });

    test('complete command returns a createProduct confirmation', () async {
      final r = await AIProductActionService.resolveCommand(
        'add product: name=Pastil; price=80; stock=20; category=Meals',
        hasPermission: hasPerm,
      );
      expect(r, isNotNull);
      final action = r!.actions.single;
      expect(action.type, AIActionType.createProduct);
      expect(action.parameters['name'], 'Pastil');
      expect(action.parameters['price'], 80.0);
      expect(action.parameters['stock'], 20);
      expect(action.parameters['categoryId'], isA<int>());
    });

    test('multiline command also parses', () async {
      final r = await AIProductActionService.resolveCommand(
        'add product:\nname=Pastil\nprice=80\nstock=20\ncategory=Meals',
        hasPermission: hasPerm,
      );
      expect(r!.actions.single.type, AIActionType.createProduct);
    });

    test('missing fields are reported', () async {
      final r = await AIProductActionService.resolveCommand(
        'add product: name=Pastil',
        hasPermission: hasPerm,
      );
      expect(r, isNotNull);
      expect(
        r!.actions.where((a) => a.type == AIActionType.createProduct),
        isEmpty,
      );
      expect(r.message, contains('price'));
      expect(r.message, contains('stock'));
      expect(r.message, contains('category'));
    });

    test('invalid price is rejected', () async {
      final r = await AIProductActionService.resolveCommand(
        'add product: name=X; price=0; stock=5; category=Meals',
        hasPermission: hasPerm,
      );
      expect(r!.message, contains('greater than 0'));
    });

    test('unknown category lists available categories', () async {
      final r = await AIProductActionService.resolveCommand(
        'add product: name=X; price=10; stock=5; category=Drinks',
        hasPermission: hasPerm,
      );
      expect(r!.message, contains('Drinks'));
      expect(r.message, contains('Meals'));
    });

    test('staff command is denied', () async {
      loginAsStaff();
      final r = await AIProductActionService.resolveCommand(
        'add product: name=X; price=10; stock=5; category=Meals',
        hasPermission: hasPerm,
      );
      expect(r, isNotNull);
      expect(r!.message, contains('Owner'));
      expect(
        r.actions.any((a) => a.type == AIActionType.createProduct),
        isFalse,
      );
    });
  });

  group('createProduct execution', () {
    test('confirmed action writes the product to the database', () async {
      final response = await AIProductActionService.resolveCommand(
        'add product: name=Pastil; price=80; stock=20; category=Meals',
        hasPermission: hasPerm,
      );
      final action = response!.actions.single;

      final result = await AIProductActionService.createProduct(
        action,
        hasPermission: hasPerm,
      );
      expect(result.success, isTrue);

      final products = await ProductService().getActiveProducts();
      expect(
        products.any(
            (p) => p.name == 'Pastil' && p.price == 80.0 && p.stock == 20),
        isTrue,
      );
    });

    test('duplicate name in the same category is rejected', () async {
      final response = await AIProductActionService.resolveCommand(
        'add product: name=Pastil; price=80; stock=20; category=Meals',
        hasPermission: hasPerm,
      );
      final action = response!.actions.single;

      final first = await AIProductActionService.createProduct(
        action,
        hasPermission: hasPerm,
      );
      expect(first.success, isTrue);

      final second = await AIProductActionService.createProduct(
        action,
        hasPermission: hasPerm,
      );
      expect(second.success, isFalse);
      expect(second.message, contains('already exists'));
    });

    test('staff execution is denied even with a prepared action', () async {
      final response = await AIProductActionService.resolveCommand(
        'add product: name=Pastil; price=80; stock=20; category=Meals',
        hasPermission: hasPerm,
      );
      final action = response!.actions.single;
      loginAsStaff();

      final result = await AIProductActionService.createProduct(
        action,
        hasPermission: hasPerm,
      );
      expect(result.success, isFalse);
    });
  });

  group('extractModelAction', () {
    test('parses the ACTION block and strips it from the text', () async {
      const raw = 'Sure, I can prepare that for you.\n'
          'ACTION:create_product\n'
          'name=Pastil\nprice=80\nstock=20\ncategory=Meals\n'
          'END_ACTION';
      final ex = await AIProductActionService.extractModelAction(
        raw,
        hasPermission: hasPerm,
      );
      expect(ex, isNotNull);
      expect(ex!.action, isNotNull);
      expect(ex.cleanedText, contains('prepare that'));
      expect(ex.cleanedText, isNot(contains('ACTION')));
    });

    test('missing fields produce a notice instead of an action', () async {
      const raw = 'Let me prepare that.\n'
          'ACTION:create_product\nname=Pastil\nEND_ACTION';
      final ex = await AIProductActionService.extractModelAction(
        raw,
        hasPermission: hasPerm,
      );
      expect(ex!.action, isNull);
      expect(ex.notice, isNotNull);
      expect(ex.notice, contains('price'));
    });

    test('non-owner sessions get a permission notice', () async {
      loginAsStaff();
      const raw = 'Here you go.\n'
          'ACTION:create_product\nname=X\nprice=5\nstock=1\ncategory=Meals\n'
          'END_ACTION';
      final ex = await AIProductActionService.extractModelAction(
        raw,
        hasPermission: hasPerm,
      );
      expect(ex!.action, isNull);
      expect(ex.notice, contains('Owner'));
    });
  });
}
