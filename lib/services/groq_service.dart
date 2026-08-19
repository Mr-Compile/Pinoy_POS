import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Result of a Groq chat completion request.
class GroqResult {
  final bool success;
  final String? content;
  final String? errorMessage;
  final bool isAuthError;
  final bool isNetworkError;

  GroqResult({
    required this.success,
    this.content,
    this.errorMessage,
    this.isAuthError = false,
    this.isNetworkError = false,
  });
}

/// Thin HTTP client for the Groq chat/completions endpoint.
///
/// The API key is passed in per-request by the calling service
/// ([AIAdvisorService]) which reads it from [SettingsService]. This class
/// never stores the key and never logs it.
class GroqService {
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  /// Sends a chat completion request to Groq.
  ///
  /// [apiKey] is the Groq API key (never stored here).
  /// [model] is the Groq model id (e.g. "llama-3.3-70b-versatile").
  /// [systemPrompt] sets the assistant context.
  /// [userMessage] is the user's query.
  ///
  /// Returns a [GroqResult]. On failure, [GroqResult.errorMessage] contains
  /// a safe, user-facing message — never the raw API key, headers, or stack
  /// trace.
  Future<GroqResult> chatCompletion({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userMessage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.7,
          'max_tokens': 1024,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = body['choices'] as List<dynamic>;
        if (choices.isEmpty) {
          return GroqResult(
            success: false,
            errorMessage: 'The AI returned an empty response. Please try again.',
          );
        }
        final content =
            (choices[0] as Map<String, dynamic>)['message']['content'] as String;
        return GroqResult(success: true, content: content.trim());
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return GroqResult(
          success: false,
          isAuthError: true,
          errorMessage:
              'AI Advisor could not authenticate. Please ask an administrator to verify the Groq API key.',
        );
      }

      if (response.statusCode == 429) {
        return GroqResult(
          success: false,
          errorMessage:
              'The AI service rate limit was reached. Please try again in a moment.',
        );
      }

      // Other HTTP errors — return a generic message without the body.
      return GroqResult(
        success: false,
        errorMessage:
            'The AI service returned an error (HTTP ${response.statusCode}). Please try again.',
      );
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
    } catch (e) {
      return GroqResult(
        success: false,
        errorMessage:
            'The advisor could not complete the analysis. Please try again.',
      );
    }
  }
}
