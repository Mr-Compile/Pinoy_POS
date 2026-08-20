import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralized Groq API endpoint configuration.
///
/// The base URL and endpoint paths are defined here in ONE place. No other
/// file in the codebase hardcodes a Groq URL. This prevents the duplicate-
/// path-segment / missing-/openai/v1 problem that caused the original 404.
class GroqEndpoints {
  GroqEndpoints._();

  /// Groq API base. Always includes the OpenAI-compatible path prefix.
  static const String baseUrl = 'https://api.groq.com/openai/v1';

  /// Chat completions endpoint (POST).
  static const String chatCompletions = '$baseUrl/chat/completions';

  /// Models listing endpoint (GET).
  static const String models = '$baseUrl/models';
}

/// A single Groq model returned by the Models API.
class GroqModel {
  final String id;
  final String ownedBy;
  final bool active;
  final int? contextWindow;

  GroqModel({
    required this.id,
    required this.ownedBy,
    required this.active,
    this.contextWindow,
  });

  factory GroqModel.fromJson(Map<String, dynamic> json) {
    return GroqModel(
      id: json['id'] as String,
      ownedBy: (json['owned_by'] as String?) ?? 'Unknown',
      active: (json['active'] as bool?) ?? true,
      contextWindow: (json['context_window'] as int?),
    );
  }
}

/// Result of a Groq chat completion request.
class GroqResult {
  final bool success;
  final String? content;
  final String? errorMessage;
  final bool isAuthError;
  final bool isNetworkError;
  final bool isModelError;
  final bool isRateLimit;
  final int? statusCode;

  GroqResult({
    required this.success,
    this.content,
    this.errorMessage,
    this.isAuthError = false,
    this.isNetworkError = false,
    this.isModelError = false,
    this.isRateLimit = false,
    this.statusCode,
  });
}

/// Result of a Groq models list request.
class GroqModelsResult {
  final bool success;
  final List<GroqModel> models;
  final String? errorMessage;
  final bool isAuthError;
  final bool isNetworkError;
  final int? statusCode;

  GroqModelsResult({
    required this.success,
    this.models = const [],
    this.errorMessage,
    this.isAuthError = false,
    this.isNetworkError = false,
    this.statusCode,
  });
}

/// Result of a Test Connection request.
class GroqTestResult {
  final bool success;
  final String? message;
  final List<GroqModel> models;
  final bool isAuthError;
  final bool isNetworkError;
  final bool isServerError;

  GroqTestResult({
    required this.success,
    this.message,
    this.models = const [],
    this.isAuthError = false,
    this.isNetworkError = false,
    this.isServerError = false,
  });
}

/// Thin HTTP client for the Groq API.
///
/// The API key is passed in per-request by the calling service
/// ([AIAdvisorService] or [SettingsService]) which reads it from
/// [SettingsService]. This class never stores the key and never logs it.
///
/// All endpoints are centralized in [GroqEndpoints] — no URL is constructed
/// ad-hoc anywhere in this file or the codebase.
class GroqService {
  /// Sends a chat completion request to Groq.
  ///
  /// [apiKey] is the Groq API key (never stored here, never logged).
  /// [model] is the Groq model id (e.g. "llama-3.3-70b-versatile").
  /// [systemPrompt] sets the assistant context.
  /// [messages] is the conversation history (role + content pairs).
  ///
  /// Returns a [GroqResult]. On failure, [GroqResult.errorMessage] contains
  /// a safe, user-facing message — never the raw API key, headers, or stack
  /// trace.
  Future<GroqResult> chatCompletion({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    final url = Uri.parse(GroqEndpoints.chatCompletions);

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...messages,
          ],
          'temperature': 0.7,
          'max_tokens': 2048,
        }),
      ).timeout(const Duration(seconds: 45));

      _logStatus('chatCompletion', response.statusCode, model);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = body['choices'] as List<dynamic>;
        if (choices.isEmpty) {
          return GroqResult(
            success: false,
            statusCode: 200,
            errorMessage:
                'The AI returned an empty response. Please try again.',
          );
        }
        final content =
            (choices[0] as Map<String, dynamic>)['message']['content']
                as String;
        return GroqResult(
          success: true,
          content: content.trim(),
          statusCode: 200,
        );
      }

      return _mapError(response);
    } on SocketException catch (_) {
      return GroqResult(
        success: false,
        isNetworkError: true,
        errorMessage:
            'No internet connection. AI Advisor requires an internet connection to function.',
      );
    } on http.ClientException catch (_) {
      return GroqResult(
        success: false,
        isNetworkError: true,
        errorMessage:
            'No internet connection. AI Advisor requires an internet connection to function.',
      );
    } on TimeoutException catch (_) {
      return GroqResult(
        success: false,
        errorMessage:
            'The AI request timed out. Please check your internet connection and try again.',
      );
    } catch (e) {
      _log('chatCompletion unexpected error (model=$model): $e');
      return GroqResult(
        success: false,
        errorMessage:
            'The advisor could not complete the analysis. Please try again.',
      );
    }
  }

  /// Fetches the list of currently available models from Groq.
  ///
  /// Calls `GET https://api.groq.com/openai/v1/models` with the provided
  /// API key. Returns only active models suitable for chat completions.
  Future<GroqModelsResult> listModels({required String apiKey}) async {
    final url = Uri.parse(GroqEndpoints.models);

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 15));

      _logStatus('listModels', response.statusCode, null);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as List<dynamic>;
        final models = <GroqModel>[];
        for (final item in data) {
          final m = GroqModel.fromJson(item as Map<String, dynamic>);
          // Only include active models.
          if (m.active) {
            models.add(m);
          }
        }
        return GroqModelsResult(
          success: true,
          models: models,
          statusCode: 200,
        );
      }

      // Map error.
      if (response.statusCode == 401 || response.statusCode == 403) {
        return GroqModelsResult(
          success: false,
          isAuthError: true,
          statusCode: response.statusCode,
          errorMessage:
              'Invalid Groq API key. Please check the key and try again.',
        );
      }
      if (response.statusCode == 429) {
        return GroqModelsResult(
          success: false,
          statusCode: 429,
          errorMessage:
              'Groq rate limit reached. Please wait a moment and try again.',
        );
      }

      return GroqModelsResult(
        success: false,
        statusCode: response.statusCode,
        errorMessage:
            'Could not fetch models from Groq (HTTP ${response.statusCode}).',
      );
    } on SocketException catch (_) {
      return GroqModelsResult(
        success: false,
        isNetworkError: true,
        errorMessage: 'No internet connection. Cannot reach Groq.',
      );
    } on http.ClientException catch (_) {
      return GroqModelsResult(
        success: false,
        isNetworkError: true,
        errorMessage: 'No internet connection. Cannot reach Groq.',
      );
    } on TimeoutException catch (_) {
      return GroqModelsResult(
        success: false,
        errorMessage: 'Request timed out. Please try again.',
      );
    } catch (e) {
      _log('listModels unexpected error: $e');
      return GroqModelsResult(
        success: false,
        errorMessage: 'Could not fetch models. Please try again.',
      );
    }
  }

  /// Tests the Groq API connection by fetching the models list.
  ///
  /// This is the authoritative "Test Connection" — it only reports success
  /// when a real HTTP 200 response with valid model data is received.
  /// No fake success.
  Future<GroqTestResult> testConnection({required String apiKey}) async {
    final modelsResult = await listModels(apiKey: apiKey);

    if (modelsResult.success) {
      return GroqTestResult(
        success: true,
        message: 'Connected. ${modelsResult.models.length} models available.',
        models: modelsResult.models,
      );
    }

    return GroqTestResult(
      success: false,
      message: modelsResult.errorMessage,
      isAuthError: modelsResult.isAuthError,
      isNetworkError: modelsResult.isNetworkError,
      isServerError: !modelsResult.isAuthError &&
          !modelsResult.isNetworkError &&
          modelsResult.statusCode != null &&
          modelsResult.statusCode! >= 500,
    );
  }

  /// Maps an HTTP error response to a user-facing [GroqResult].
  ///
  /// Handles:
  /// - 401/403 → Invalid API key
  /// - 404 → Model not found / endpoint configuration error
  /// - 429 → Rate limit
  /// - 5xx → Server error
  /// - other → generic error
  ///
  /// NEVER includes the API key, headers, or raw response body in the
  /// user-facing message.
  GroqResult _mapError(http.Response response) {
    final status = response.statusCode;

    // Try to extract the Groq error type for better messaging.
    String? errorType;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      errorType = error?['type'] as String?;
      // Also check for "code" field
      errorType ??= error?['code'] as String?;
    } catch (_) {
      // Body wasn't JSON — ignore.
    }

    if (status == 401 || status == 403) {
      return GroqResult(
        success: false,
        statusCode: status,
        isAuthError: true,
        errorMessage:
            'AI Advisor could not authenticate. Please ask an administrator to verify the Groq API key.',
      );
    }

    if (status == 404) {
      // 404 on chat/completions means the model ID was not found.
      // Groq returns "model_not_found" or "invalid_request_error" with a
      // message like "The model 'X' does not exist".
      return GroqResult(
        success: false,
        statusCode: 404,
        isModelError: true,
        errorMessage:
            'The selected AI model is no longer available. Please ask an administrator to select a different model in AI Configuration.',
      );
    }

    if (status == 429) {
      return GroqResult(
        success: false,
        statusCode: 429,
        isRateLimit: true,
        errorMessage:
            'The AI service rate limit was reached. Please try again in a moment.',
      );
    }

    if (status >= 500) {
      return GroqResult(
        success: false,
        statusCode: status,
        errorMessage:
            'The AI service is experiencing issues (HTTP $status). Please try again later.',
      );
    }

    return GroqResult(
      success: false,
      statusCode: status,
      errorMessage:
          'The AI service returned an error (HTTP $status). Please try again.',
    );
  }

  /// Logs the HTTP status for a request. In debug mode this prints the
  /// status code, endpoint name, and model ID — NEVER the API key, headers,
  /// or request body.
  void _logStatus(String endpoint, int statusCode, String? model) {
    if (kDebugMode) {
      final modelStr = model != null ? ' model=$model' : '';
      debugPrint('[GroqService] $endpoint → HTTP $statusCode$modelStr');
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GroqService] $message');
    }
  }
}
