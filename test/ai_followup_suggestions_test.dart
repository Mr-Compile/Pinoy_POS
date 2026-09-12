import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';
import 'package:pinoy_pos/services/ai_skill_service.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Tests for adaptive follow-up suggestion chips:
///
///   user query → detectIntent → role-scoped follow-up pool →
///   dedup against already-asked questions → chips below the AI bubble
void main() {
  setUp(() {
    SessionManager.resetForTest();
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  group('BusinessIntelligenceService.generateFollowUpSuggestions', () {
    test('owner sales query returns sales follow-ups', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How are my sales today?',
        role: UserRole.owner,
      );

      expect(followUps, hasLength(3));
      expect(followUps, contains('What products are selling the most?'));
      expect(followUps, contains('Which products are low in stock?'));
    });

    test('owner top-products query pivots to stock follow-ups', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'What products are selling the most?',
        role: UserRole.owner,
      );

      expect(followUps, hasLength(3));
      expect(followUps.first, 'Which products are low in stock?');
      expect(followUps, contains('What should I restock soon?'));
    });

    test('staff query returns staff-scoped follow-ups', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How much did I sell today?',
        role: UserRole.staff,
      );

      expect(followUps, hasLength(3));
      expect(
        followUps.first,
        'Which products sell best in my transactions?',
      );
      // Staff must never be offered business-wide questions.
      expect(followUps, isNot(contains('Give me a business summary.')));
    });

    test('admin query returns admin-scoped follow-ups', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How many users do we have?',
        role: UserRole.admin,
      );

      expect(followUps, hasLength(3));
      expect(followUps, contains('Show recent system activity.'));
      expect(followUps, contains('When was the latest backup?'));
    });

    test('general query falls back to the role pool', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'hello there',
        role: UserRole.owner,
      );

      expect(followUps, hasLength(3));
      expect(followUps.first, 'How are my sales today?');
    });

    test('excludes questions already asked in the conversation', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How are my sales today?',
        role: UserRole.owner,
        exclude: {'What products are selling the most?'},
      );

      expect(followUps, hasLength(3));
      expect(
        followUps,
        isNot(contains('What products are selling the most?')),
      );
      // The pool pads from the role fallback to stay at 3.
      expect(followUps, contains('What should I restock soon?'));
    });

    test('exclusion matching ignores case and punctuation', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How are my sales today?',
        role: UserRole.owner,
        exclude: {'what products are selling the most'},
      );

      expect(
        followUps,
        isNot(contains('What products are selling the most?')),
      );
    });

    test('never suggests the question that was just asked', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'Give me a business summary.',
        role: UserRole.owner,
      );

      expect(followUps, isNot(contains('Give me a business summary.')));
    });

    test('respects maxSuggestions', () {
      final service = BusinessIntelligenceService();

      final followUps = service.generateFollowUpSuggestions(
        'How are my sales today?',
        role: UserRole.owner,
        maxSuggestions: 2,
      );

      expect(followUps, hasLength(2));
    });

    test('uses the session user role when none is provided', () {
      SessionManager().setCurrentUser(_staffUser);
      final service = BusinessIntelligenceService();

      final followUps =
          service.generateFollowUpSuggestions('How much did I sell today?');

      expect(followUps.first, 'Which products sell best in my transactions?');
    });
  });

  group('AIAdvisorService.getFollowUpSuggestions', () {
    test('delegates to the BI layer for permitted users', () {
      SessionManager().setCurrentUser(_ownerUser);
      final service = AIAdvisorService();

      final followUps = service.getFollowUpSuggestions(
        'How are my sales today?',
      );

      expect(followUps, isNotEmpty);
    });
  });

  group('AIAdvisorChatNotifier follow-ups', () {
    test('assistant message carries adaptive follow-ups', () async {
      final container = _createContainer();
      _activateChat(container);

      await container
          .read(aiAdvisorChatProvider.notifier)
          .sendQuery('test question');

      final assistant = container
          .read(aiAdvisorChatProvider)
          .messages
          .lastWhere((m) => !m.isUser);

      expect(assistant.followUps, isNotEmpty);
      expect(assistant.effectiveSuggestions, assistant.followUps);
    });

    test('follow-ups exclude questions already asked', () async {
      final container = _createContainer();
      _activateChat(container);

      await container
          .read(aiAdvisorChatProvider.notifier)
          .sendQuery('What products are selling the most?');

      await container
          .read(aiAdvisorChatProvider.notifier)
          .sendQuery('test question');

      final assistant = container
          .read(aiAdvisorChatProvider)
          .messages
          .lastWhere((m) => !m.isUser);

      expect(
        assistant.followUps,
        isNot(contains('What products are selling the most?')),
      );
    });
  });
}

final _ownerUser = User(
  id: 1,
  username: 'owner',
  passwordHash: '',
  role: UserRole.owner,
  fullName: 'Test Owner',
  createdAt: DateTime.now(),
);

final _staffUser = User(
  id: 2,
  username: 'staff',
  passwordHash: '',
  role: UserRole.staff,
  fullName: 'Test Staff',
  createdAt: DateTime.now(),
);

void _activateChat(ProviderContainer container) {
  container.read(aiAdvisorChatProvider.notifier).state = AIAdvisorChatState(
    configStatus: AIConfigStatus.active,
    remainingQueries: AppConstants.maxDailyAIQueries,
  );
}

ProviderContainer _createContainer() {
  SessionManager().setCurrentUser(_ownerUser);
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWith((ref) => _FakeAuthService()),
      aiAdvisorServiceProvider.overrideWith(
        (ref) => AIAdvisorService(
          groqService: _FakeGroqService(),
          aiUsageService: _FakeAIUsageService(),
          settingsService: _FakeSettingsService(),
          biService: _FakeBIService(),
          skillService: _FakeSkillService(),
        ),
      ),
      aiUsageServiceProvider.overrideWith((ref) => _FakeAIUsageService()),
      settingsServiceProvider.overrideWith((ref) => _FakeSettingsService()),
    ],
  );
}

// ── Fakes ───────────────────────────────────────────────────────────

class _FakeGroqService extends GroqService {
  @override
  Future<GroqResult> chatCompletion({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    return GroqResult(
      success: true,
      content: 'Here is a plain answer.',
      statusCode: 200,
    );
  }

  @override
  Future<GroqModelsResult> listModels({required String apiKey}) async {
    return GroqModelsResult(
      success: true,
      models: [
        GroqModel(id: 'llama-fake', ownedBy: 'test', active: true),
      ],
    );
  }
}

class _FakeAIUsageService extends AIUsageService {
  @override
  Future<bool> canUseAI() async => true;

  @override
  Future<int> getTodayUsageCount() async => 0;

  @override
  Future<bool> recordQuery(String query, String? response) async => true;
}

class _FakeSettingsService extends SettingsService {
  @override
  Future<String?> getGroqApiKey() async => 'fake-api-key';

  @override
  Future<String> getGroqModel() async => 'llama-fake';

  @override
  Future<bool> isGroqConfigured() async => true;
}

/// Intent detection is inherited for follow-up generation; only the
/// data-gathering path is stubbed so no database is touched.
class _FakeBIService extends BusinessIntelligenceService {
  @override
  Future<BusinessFacts> gatherFacts(
    DetectedIntent detected, {
    UserRole? role,
    int? userId,
  }) async {
    return BusinessFacts(
      context: '---\nStore: Test Store\n---',
      intent: detected.intent,
      hasData: true,
    );
  }
}

/// Skips the asset bundle entirely — skill guidance is empty in tests.
class _FakeSkillService extends AISkillService {
  @override
  Future<String> buildGuidance(
    String query,
    BusinessIntent intent,
    UserRole? role,
  ) async =>
      '';
}

class _FakeAuthService extends AuthService {
  @override
  Future<SessionStatus> restoreSession() async => SessionStatus.active;

  @override
  bool hasPermission(String permission) {
    return permission == 'use_ai_advisor' ||
        permission == 'view_ai_advisor' ||
        permission == 'manage_ai_config';
  }
}
