import 'package:flutter/foundation.dart';

/// A structured, local-first AI assistant response that can contain
/// natural language, step-by-step instructions, navigation actions,
/// and follow-up suggestions.
///
/// This model decouples the AI's text output from the application's
/// rendering of instructions and navigation. The application—not the
/// model—has final authority over which actions are shown, based on the
/// current user's permissions and the registered destination list.
class AIResponse {
  final String message;
  final List<AIInstruction> instructions;
  final List<AIAction> actions;
  final List<String> suggestions;

  const AIResponse({
    required this.message,
    this.instructions = const [],
    this.actions = const [],
    this.suggestions = const [],
  });

  /// Returns true when the response has no instructions, actions, or
  /// suggestions beyond a plain message.
  bool get isPlainMessage =>
      instructions.isEmpty && actions.isEmpty && suggestions.isEmpty;

  AIResponse copyWith({
    String? message,
    List<AIInstruction>? instructions,
    List<AIAction>? actions,
    List<String>? suggestions,
  }) {
    return AIResponse(
      message: message ?? this.message,
      instructions: instructions ?? this.instructions,
      actions: actions ?? this.actions,
      suggestions: suggestions ?? this.suggestions,
    );
  }

  /// Filters [actions] to those whose destinations are allowed for the
  /// current user, returning a new [AIResponse] with only safe actions.
  AIResponse filterActions(bool Function(AIAction) isAllowed) {
    return copyWith(actions: actions.where(isAllowed).toList());
  }

  @override
  String toString() {
    return 'AIResponse(message: $message, instructions: ${instructions.length}, '
        'actions: ${actions.length}, suggestions: ${suggestions.length})';
  }
}

/// A single instruction step, optionally tied to a navigation action.
class AIInstruction {
  final String text;
  final AIAction? action;

  const AIInstruction({
    required this.text,
    this.action,
  });

  @override
  String toString() => 'AIInstruction(text: $text, action: $action)';
}

/// An actionable item the AI can request. The application validates the
/// [destination] against the registered [AINavigationRegistry] and the
/// user's permissions before executing it.
class AIAction {
  final AIActionType type;
  final String destination;
  final String label;
  final Map<String, dynamic> parameters;

  const AIAction({
    required this.type,
    required this.destination,
    required this.label,
    this.parameters = const {},
  });

  /// True when this action requires a contextual parameter such as
  /// a sale or product ID.
  bool get hasParameters => parameters.isNotEmpty;

  @override
  String toString() {
    return 'AIAction(type: $type, destination: $destination, label: $label, '
        'parameters: $parameters)';
  }

  @override
  bool operator ==(Object other) =>
      other is AIAction &&
      other.type == type &&
      other.destination == destination &&
      other.label == label &&
      mapEquals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(type, destination, label, parameters);
}

/// Supported AI action types. The application must validate and execute
/// each type differently; the model only requests them.
enum AIActionType {
  /// Open a top-level screen.
  navigate,

  /// Open a detail view with parameters (e.g., sale details).
  openDetail,

  /// Open a filtered list view (e.g., low stock).
  openFilteredView,

  /// A step-by-step instruction with no navigation side effect.
  instruction,

  /// A follow-up question or suggested query.
  suggestion,

  /// Open an external URL from the allowlist.
  externalLink,
}
