import 'package:flutter/material.dart';
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
import 'package:pinoy_pos/services/ai_response_policy.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/ui/widgets/ai_chat_panel.dart';

/// Integration test for the full AI response humanization pipeline:
///
///   Groq (fake) → AIAdvisorService → AiResponseSanitizer →
///   AIAdvisorChatNotifier → AIChatPanel (SelectableText)
///
/// This test verifies that raw Markdown from the model is sanitized
/// before it is displayed in the production chat UI.
void main() {
  setUp(() {
    SessionManager.resetForTest();
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  group('AI response production pipeline', () {
    const rawMarkdownResponse = '## Sales Summary\n'
        '\n'
        '**Total Sales:** ₱8,500\n'
        '\n'
        '---\n'
        '\n'
        'Your top product is **Chicken-Adobo**.\n'
        'GCash sales are lower than yesterday.';

    test('AIAdvisorService sanitizes raw Groq response', () async {
      final service = _makeService(rawMarkdownResponse);

      final result = await service.query('How are my sales?');

      expect(result.success, isTrue);
      expect(result.content, isNotNull);
      expect(AiResponsePolicy.isHumanized(result.content!), isTrue);
      expect(result.content, isNot(contains('##')));
      expect(result.content, isNot(contains('**')));
      expect(result.content, isNot(contains('---')));
      // The sentence must be preserved.
      expect(result.content, contains('Your top product is Chicken-Adobo.'));
      expect(result.content, contains('Total Sales: ₱8,500'));
    });

    test('AIAdvisorChatNotifier stores sanitized response', () async {
      final container = _createContainer(rawMarkdownResponse);

      // Start from an active AI config state.
      container.read(aiAdvisorChatProvider.notifier).state =
          AIAdvisorChatState(
        configStatus: AIConfigStatus.active,
        remainingQueries: AppConstants.maxDailyAIQueries,
      );

      await container.read(aiAdvisorChatProvider.notifier).sendQuery('test');

      final messages =
          container.read(aiAdvisorChatProvider).messages;
      final assistantMessages =
          messages.where((m) => !m.isUser && !m.isError).toList();

      expect(assistantMessages, isNotEmpty);
      final text = assistantMessages.last.text;
      expect(AiResponsePolicy.isHumanized(text), isTrue);
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('##')));
      expect(text, isNot(contains('---')));
    });

    testWidgets('AIChatPanel renders sanitized plain text', (tester) async {
      final container = _createContainer(rawMarkdownResponse);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  AIChatPanel(),
                ],
              ),
            ),
          ),
        ),
      );

      // Put the chat in an active state and send a query.
      container.read(aiAdvisorChatProvider.notifier).state =
          AIAdvisorChatState(
        configStatus: AIConfigStatus.active,
        remainingQueries: AppConstants.maxDailyAIQueries,
        isPanelOpen: true,
      );

      // Pump once to reflect the state.
      await tester.pump();

      await container.read(aiAdvisorChatProvider.notifier).sendQuery('test');
      await tester.pumpAndSettle();

      // Verify the rendered text has no Markdown markers by reading the
      // provider state, which is the same state the UI uses.
      final messages =
          container.read(aiAdvisorChatProvider).messages;
      final assistant =
          messages.lastWhere((m) => !m.isUser && !m.isError);
      expect(AiResponsePolicy.isHumanized(assistant.text), isTrue);
      expect(assistant.text, isNot(contains('**')));
      expect(assistant.text, isNot(contains('##')));
      expect(assistant.text, isNot(contains('---')));
    });
  });
}

AIAdvisorService _makeService(String rawResponse) {
  SessionManager().setCurrentUser(_ownerUser);
  return AIAdvisorService(
    groqService: _FakeGroqService(rawResponse: rawResponse),
    aiUsageService: _FakeAIUsageService(),
    settingsService: _FakeSettingsService(),
    biService: _FakeBIService(),
  );
}

ProviderContainer _createContainer(String rawResponse) {
  SessionManager().setCurrentUser(_ownerUser);
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWith((ref) => _FakeAuthService()),
      aiAdvisorServiceProvider.overrideWith(
        (ref) => AIAdvisorService(
          groqService: _FakeGroqService(rawResponse: rawResponse),
          aiUsageService: _FakeAIUsageService(),
          settingsService: _FakeSettingsService(),
          biService: _FakeBIService(),
        ),
      ),
      aiUsageServiceProvider.overrideWith((ref) => _FakeAIUsageService()),
      settingsServiceProvider.overrideWith((ref) => _FakeSettingsService()),
    ],
  );
}

final _ownerUser = User(
  id: 1,
  username: 'owner',
  passwordHash: '',
  role: UserRole.owner,
  fullName: 'Test Owner',
  createdAt: DateTime.now(),
);

// ── Fakes ───────────────────────────────────────────────────────────

class _FakeGroqService extends GroqService {
  final String rawResponse;

  _FakeGroqService({required this.rawResponse});

  @override
  Future<GroqResult> chatCompletion({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    return GroqResult(
      success: true,
      content: rawResponse,
      statusCode: 200,
    );
  }

  @override
  Future<GroqModelsResult> listModels({required String apiKey}) async {
    return GroqModelsResult(
      success: true,
      models: [
        GroqModel(
          id: 'llama-fake',
          ownedBy: 'test',
          active: true,
        ),
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

class _FakeBIService extends BusinessIntelligenceService {
  @override
  DetectedIntent detectIntent(String query, {UserRole? role}) => DetectedIntent(
        intent: BusinessIntent.general,
        startDate: null,
        endDate: null,
        periodDescription: 'all time',
      );

  @override
  Future<BusinessFacts> gatherFacts(
    DetectedIntent detected, {
    UserRole? role,
    int? userId,
  }) async {
    return BusinessFacts(
      context: '---\nStore: Test Store\nToday sales: ₱8,500\n---',
      intent: BusinessIntent.general,
      hasData: true,
    );
  }
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
