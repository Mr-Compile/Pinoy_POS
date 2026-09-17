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

  /// Serializes this response so a chat message can be persisted and
  /// restored with its instructions, actions, and suggestions intact.
  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'instructions': [for (final i in instructions) i.toJson()],
      'actions': [for (final a in actions) a.toJson()],
      'suggestions': suggestions,
    };
  }

  /// Rebuilds an [AIResponse] from [AIResponse.toJson]. Unrecognized or
  /// malformed entries are skipped so a row written by a different app
  /// version can never break conversation restore.
  factory AIResponse.fromJson(Map<String, dynamic> json) {
    final instructions = <AIInstruction>[];
    final rawInstructions = json['instructions'];
    if (rawInstructions is List) {
      for (final e in rawInstructions) {
        if (e is Map) {
          final parsed = AIInstruction.tryParse(e.cast<String, dynamic>());
          if (parsed != null) instructions.add(parsed);
        }
      }
    }

    final actions = <AIAction>[];
    final rawActions = json['actions'];
    if (rawActions is List) {
      for (final e in rawActions) {
        if (e is Map) {
          final parsed = AIAction.tryParse(e.cast<String, dynamic>());
          if (parsed != null) actions.add(parsed);
        }
      }
    }

    final suggestions = <String>[];
    final rawSuggestions = json['suggestions'];
    if (rawSuggestions is List) {
      for (final s in rawSuggestions) {
        if (s != null) suggestions.add(s.toString());
      }
    }

    return AIResponse(
      message: json['message'] as String? ?? '',
      instructions: instructions,
      actions: actions,
      suggestions: suggestions,
    );
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

  Map<String, dynamic> toJson() => {
        'text': text,
        if (action != null) 'action': action!.toJson(),
      };

  /// Parses a JSON map into an [AIInstruction]. Returns null when the map
  /// does not contain a usable `text` value.
  static AIInstruction? tryParse(Map<String, dynamic> json) {
    final text = json['text'];
    if (text is! String || text.isEmpty) return null;
    final rawAction = json['action'];
    AIAction? action;
    if (rawAction is Map) {
      action = AIAction.tryParse(rawAction.cast<String, dynamic>());
    }
    return AIInstruction(text: text, action: action);
  }

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

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'destination': destination,
        'label': label,
        'parameters': parameters,
      };

  /// Parses a JSON map into an [AIAction]. Returns null when the type is
  /// unknown or required fields are missing — the caller should drop the
  /// action rather than render something un-executable.
  static AIAction? tryParse(Map<String, dynamic> json) {
    final typeName = json['type'];
    final destination = json['destination'];
    final label = json['label'];
    if (typeName is! String || destination is! String || label is! String) {
      return null;
    }

    AIActionType? type;
    for (final t in AIActionType.values) {
      if (t.name == typeName) {
        type = t;
        break;
      }
    }
    if (type == null) return null;

    final rawParams = json['parameters'];
    return AIAction(
      type: type,
      destination: destination,
      label: label,
      parameters: rawParams is Map
          ? rawParams.cast<String, dynamic>()
          : const {},
    );
  }

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

  /// Request creation of a catalog product. The application validates the
  /// supplied parameters (name, price, stock, categoryId) and runs the
  /// write through ProductService only after the user confirms.
  createProduct,
}
