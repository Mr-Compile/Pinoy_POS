import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_chat_message.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/repositories/ai_chat_message_repository.dart';

/// Loads, appends, and clears the persisted AI advisor conversation.
///
/// Conversation history is stored in `ai_chat_messages` keyed by the
/// authenticated user's id, so accounts sharing a device keep separate
/// conversations. History survives app restarts and is only removed
/// when the user explicitly starts a new conversation
/// ([clearConversation]).
class AIChatHistoryService {
  final AIChatMessageRepository _repository;
  final SessionManager _sessionManager;

  AIChatHistoryService({
    AIChatMessageRepository? repository,
    SessionManager? sessionManager,
  })  : _repository = repository ?? AIChatMessageRepository(),
        _sessionManager = sessionManager ?? SessionManager();

  /// Bounds how many messages are stored per user — the table stays
  /// small on long-running installs while a conversation remains
  /// effectively "unlimited" in practice.
  static const int maxStoredMessages = 200;

  int? get _currentUserId => _sessionManager.currentUser?.id;

  bool get _canUseAdvisor => _sessionManager.hasPermission('use_ai_advisor');

  /// Returns the stored conversation for the current user,
  /// oldest → newest, sanitized for display (stale one-shot write
  /// actions such as "create this product" are dropped). Returns an
  /// empty list when nobody is logged in or the user lacks the
  /// `use_ai_advisor` permission.
  Future<List<AIChatMessage>> loadConversation() async {
    final userId = _currentUserId;
    if (!_canUseAdvisor || userId == null) return const [];
    final messages = await _repository.getRecentForUser(
      userId,
      limit: maxStoredMessages,
    );
    return [for (final m in messages) _sanitizeRestored(m)];
  }

  /// Persists a single newly appended message. No-ops without an
  /// authorized user. Also prunes the tail so the table never grows
  /// beyond [maxStoredMessages] per user.
  Future<void> appendMessage(AIChatMessage message) async {
    final userId = _currentUserId;
    if (!_canUseAdvisor || userId == null) return;
    await _repository.insertForUser(userId, message);
    await _repository.pruneForUser(userId, keep: maxStoredMessages);
  }

  /// Deletes the stored conversation for the current user. Only called
  /// when the user explicitly chooses "New conversation".
  Future<void> clearConversation() async {
    final userId = _currentUserId;
    if (userId == null) return;
    await _repository.deleteForUser(userId);
  }

  /// Strips write-confirmation actions (e.g. create-product buttons)
  /// from restored assistant messages — those were one-shot prompts
  /// tied to the session that produced them, so re-showing them after a
  /// restart would resurrect a stale confirmation flow. Navigation and
  /// instruction actions stay: they remain valid deep links.
  AIChatMessage _sanitizeRestored(AIChatMessage message) {
    final response = message.response;
    if (response == null) return message;

    final actions = response.actions
        .where((a) => a.type != AIActionType.createProduct)
        .toList();
    final instructions = [
      for (final i in response.instructions)
        i.action?.type == AIActionType.createProduct
            ? AIInstruction(text: i.text)
            : i,
    ];

    if (actions.length == response.actions.length &&
        instructions.length == response.instructions.length &&
        _sameInstructionActions(instructions, response.instructions)) {
      return message;
    }

    return message.copyWith(
      response: response.copyWith(
        actions: actions,
        instructions: instructions,
      ),
    );
  }

  bool _sameInstructionActions(
    List<AIInstruction> a,
    List<AIInstruction> b,
  ) {
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].action, b[i].action)) return false;
    }
    return true;
  }
}
