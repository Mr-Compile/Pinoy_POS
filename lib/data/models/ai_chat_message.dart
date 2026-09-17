import 'dart:convert';

import 'package:pinoy_pos/data/models/ai_response.dart';

/// A single message in the AI advisor conversation.
///
/// Messages are persisted per authenticated user in the
/// `ai_chat_messages` table so a conversation survives app restarts.
/// The conversation is only cleared when the user explicitly starts a
/// new conversation — never by app restarts, route changes, or panel
/// close.
class AIChatMessage {
  final String text;
  final AIResponse? response;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final List<String> followUps;

  AIChatMessage({
    required this.text,
    this.response,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.followUps = const [],
  });

  /// The suggestion chips to show below this message, if any.
  List<String> get effectiveSuggestions =>
      response != null && response!.suggestions.isNotEmpty
          ? response!.suggestions
          : followUps;

  /// True when this message should be rendered as a structured card.
  bool get isStructured => response != null;

  /// Serializes this message for the `ai_chat_messages` table. [userId]
  /// scopes the row to the authenticated user so conversations never
  /// leak between accounts on a shared device.
  Map<String, dynamic> toRow(int userId) {
    return {
      'user_id': userId,
      'is_user': isUser ? 1 : 0,
      'text': text,
      'is_error': isError ? 1 : 0,
      'response_json':
          response == null ? null : jsonEncode(response!.toJson()),
      'follow_ups_json': followUps.isEmpty ? null : jsonEncode(followUps),
      'created_at': timestamp.toIso8601String(),
    };
  }

  /// Rebuilds a message from a persisted row. Malformed JSON payloads are
  /// treated as absent rather than throwing — a corrupted blob must never
  /// prevent the rest of the conversation from loading.
  factory AIChatMessage.fromRow(Map<String, dynamic> map) {
    AIResponse? response;
    final rawResponse = map['response_json'];
    if (rawResponse is String && rawResponse.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawResponse);
        if (decoded is Map) {
          response = AIResponse.fromJson(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        response = null;
      }
    }

    var followUps = const <String>[];
    final rawFollowUps = map['follow_ups_json'];
    if (rawFollowUps is String && rawFollowUps.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFollowUps);
        if (decoded is List) {
          followUps = [for (final e in decoded) e.toString()];
        }
      } catch (_) {
        followUps = const <String>[];
      }
    }

    return AIChatMessage(
      text: map['text'] as String? ?? '',
      response: response,
      isUser: map['is_user'] == 1,
      timestamp: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isError: map['is_error'] == 1,
      followUps: followUps,
    );
  }

  AIChatMessage copyWith({
    String? text,
    AIResponse? response,
    bool? isUser,
    DateTime? timestamp,
    bool? isError,
    List<String>? followUps,
  }) {
    return AIChatMessage(
      text: text ?? this.text,
      response: response ?? this.response,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
      followUps: followUps ?? this.followUps,
    );
  }
}
