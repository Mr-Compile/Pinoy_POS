import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/ai_navigation_registry.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_navigation_resolver.dart';
import 'package:pinoy_pos/services/ai_navigation_service.dart';

void main() {
  group('AINavigationRegistry', () {
    test('contains the expected destination IDs', () {
      expect(AINavigationRegistry.isRegistered('dashboard'), isTrue);
      expect(AINavigationRegistry.isRegistered('products'), isTrue);
      expect(AINavigationRegistry.isRegistered('users'), isTrue);
      expect(AINavigationRegistry.isRegistered('unknown_page'), isFalse);
    });

    test('filters destinations by permission', () {
      final allowed = AINavigationRegistry.allowedFor(
        UserRole.owner,
        (permission) => true,
      );
      expect(allowed, isNotEmpty);
      expect(allowed.map((d) => d.id).contains('dashboard'), isTrue);
    });

    test('rejects unauthorized destinations for staff', () {
      final allowed = AINavigationRegistry.allowedFor(
        UserRole.staff,
        (permission) => permission == 'view_dashboard',
      );
      expect(allowed.length, 1);
      expect(allowed.first.id, 'dashboard');
    });
  });

  group('AINavigationService intent detection', () {
    test('detects "open products"', () {
      expect(
        AINavigationService.detectNavigationIntent('open products'),
        'products',
      );
    });

    test('detects "how do I add a product?"', () {
      expect(
        AINavigationService.detectNavigationIntent('how do I add a product?'),
        'products',
      );
    });

    test('detects "where are my sales?"', () {
      expect(
        AINavigationService.detectNavigationIntent('where are my sales?'),
        'sales',
      );
    });

    test('returns null for non-navigation queries', () async {
      expect(
        AINavigationService.detectNavigationIntent('what is my top product?'),
        isNull,
      );
    });
  });

  group('AINavigationService.resolveNavigationResponse', () {
    test('returns a structured response for products', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'how do I add a product?',
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_products',
      );

      expect(response, isNotNull);
      expect(response!.message, contains('Products'));
      expect(response.instructions, isNotEmpty);
      expect(response.actions, isNotEmpty);
      expect(response.actions.first.destination, 'products');
    });

    test('omits the main action when user is already on the screen', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'how do I add a product?',
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_products',
        currentDestinationId: 'products',
      );

      expect(response, isNotNull);
      expect(response!.actions, isEmpty);
      expect(response.message, contains("You're already"));
    });

    test('returns unauthorized response when permission is missing', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'open users',
        role: UserRole.staff,
        hasPermission: (permission) => permission != 'manage_users',
      );

      expect(response, isNotNull);
      expect(response!.actions, isEmpty);
      expect(response.message, contains('isn\'t available'));
    });

    test('returns null for unrecognized navigation queries', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'tell me a joke',
        role: UserRole.owner,
        hasPermission: (permission) => true,
      );

      expect(response, isNull);
    });

    test('filters suggestions to those the user can access', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'open dashboard',
        role: UserRole.staff,
        hasPermission: (permission) => permission == 'view_dashboard',
        currentDestinationId: 'dashboard',
      );

      expect(response, isNotNull);
      // Staff has no access to the related destinations dashboard suggests.
      expect(response!.suggestions, isEmpty);
    });
  });

  group('AINavigationResolver', () {
    test('canExecute rejects unknown destinations', () {
      final action = AIAction(
        type: AIActionType.navigate,
        destination: 'unknown_page',
        label: 'Open Unknown',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.owner,
          hasPermission: (permission) => true,
        ),
        isFalse,
      );
    });

    test('canExecute rejects actions that target the current screen', () {
      final action = AIAction(
        type: AIActionType.navigate,
        destination: 'products',
        label: 'Open Products',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.owner,
          hasPermission: (permission) => permission == 'view_products',
          currentDestinationId: 'products',
        ),
        isFalse,
      );
    });

    test('canExecute requires the destination permission', () {
      final action = AIAction(
        type: AIActionType.navigate,
        destination: 'users',
        label: 'Open Users',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.staff,
          hasPermission: (permission) => permission != 'manage_users',
        ),
        isFalse,
      );
    });

    test('canExecute requires the allowed role', () {
      final action = AIAction(
        type: AIActionType.navigate,
        destination: 'ai_quota',
        label: 'Open AI Quota',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.staff,
          hasPermission: (permission) => permission == 'edit_settings',
        ),
        isFalse,
      );
    });

    test('resolves a destination to metadata when allowed', () {
      final action = AIAction(
        type: AIActionType.navigate,
        destination: 'products',
        label: 'Open Products',
      );

      final destination = AINavigationResolver.resolveDestination(
        action,
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_products',
      );

      expect(destination, isNotNull);
      expect(destination!.id, 'products');
    });

  });


  group('AINavigationService deep links', () {
    test('detects "sale #1024"', () {
      expect(
        AINavigationService.detectNavigationIntent('sale #1024'),
        'sale_details',
      );
    });

    test('detects "show sale 1024"', () {
      expect(
        AINavigationService.detectNavigationIntent('show sale 1024'),
        'sale_details',
      );
    });

    test('detects "receipt for sale #1024"', () {
      expect(
        AINavigationService.detectNavigationIntent('receipt for sale #1024'),
        'receipt',
      );
    });

    test('returns structured sale detail action with saleId', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'show sale #1024',
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_sales',
      );

      expect(response, isNotNull);
      expect(response!.actions.length, 1);
      expect(response.actions.first.type, AIActionType.openDetail);
      expect(response.actions.first.destination, 'sale_details');
      expect(response.actions.first.parameters['saleId'], 1024);
      expect(response.actions.first.label, 'View Sale #1024');
    });

    test('returns structured receipt action with saleId', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'receipt for sale #1024',
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_sales',
      );

      expect(response, isNotNull);
      expect(response!.actions.length, 1);
      expect(response.actions.first.type, AIActionType.openDetail);
      expect(response.actions.first.destination, 'receipt');
      expect(response.actions.first.parameters['saleId'], 1024);
      expect(response.actions.first.label, 'Open Receipt #1024');
    });

    test('rejects sale detail when user lacks view_sales permission', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'show sale #1024',
        role: UserRole.staff,
        hasPermission: (permission) => permission != 'view_sales',
      );

      expect(response, isNotNull);
      expect(response!.actions, isEmpty);
      expect(response.message, contains('isn\'t available'));
    });

    test('omits action when already on sale detail', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'show sale #1024',
        role: UserRole.owner,
        hasPermission: (permission) => permission == 'view_sales',
        currentDestinationId: 'sale_details',
      );

      expect(response, isNotNull);
      expect(response!.actions, isEmpty);
    });
  });

  group('AINavigationService external links', () {
    test('detects support request', () {
      expect(
        AINavigationService.detectNavigationIntent('open support'),
        'support_page',
      );
    });

    test('returns external link action for support', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'i need help',
        role: UserRole.staff,
        hasPermission: (permission) => permission == 'use_ai_advisor',
      );

      expect(response, isNotNull);
      expect(response!.actions.length, 1);
      expect(response.actions.first.type, AIActionType.externalLink);
      expect(response.actions.first.destination, 'support_page');
    });

    test('rejects external link when permission is missing', () async {
      final response = await AINavigationService.resolveNavigationResponse(
        'open groq docs',
        role: UserRole.staff,
        hasPermission: (permission) => permission != 'manage_ai_config',
      );

      expect(response, isNotNull);
      expect(response!.actions, isEmpty);
      expect(response.message, contains('isn\'t available'));
    });
  });

  group('AINavigationResolver parameter validation', () {
    test('rejects sale detail without saleId', () {
      final action = AIAction(
        type: AIActionType.openDetail,
        destination: 'sale_details',
        label: 'View Sale',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.owner,
          hasPermission: (permission) => permission == 'view_sales',
        ),
        isFalse,
      );
    });

    test('rejects receipt with invalid saleId', () {
      final action = AIAction(
        type: AIActionType.openDetail,
        destination: 'receipt',
        label: 'Open Receipt',
        parameters: {'saleId': 'not-a-number'},
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.owner,
          hasPermission: (permission) => permission == 'view_sales',
        ),
        isFalse,
      );
    });

    test('rejects unknown external link destination', () {
      final action = AIAction(
        type: AIActionType.externalLink,
        destination: 'malicious_site',
        label: 'Open Malicious',
      );

      expect(
        AINavigationResolver.canExecute(
          action: action,
          role: UserRole.owner,
          hasPermission: (permission) => true,
        ),
        isFalse,
      );
    });
  });
}