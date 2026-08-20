/// Safe, user-facing AI configuration status.
///
/// The UI uses this to determine whether the AI Advisor is ready to
/// accept queries. It never exposes the API key, partial key, headers,
/// or any sensitive configuration value.
enum AIConfigStatus {
  /// Configuration is valid and the AI provider is ready.
  active,

  /// No API key has been configured (null, empty, or whitespace-only).
  notConfigured,

  /// The AI provider/service is unavailable (e.g. configuration load
  /// failure, service not initialized).
  unavailable,

  /// The configured API key was rejected by the provider (401/403).
  invalid,

  /// Status is being checked; the UI should show a loading state.
  checking,
}

/// Extension providing a human-readable label for each status.
extension AIConfigStatusLabel on AIConfigStatus {
  String get label => switch (this) {
        AIConfigStatus.active => 'AI Advisor is ready',
        AIConfigStatus.notConfigured =>
          'AI Advisor is not configured. Please ask an administrator to set up the AI API key.',
        AIConfigStatus.unavailable =>
          'AI Advisor is currently unavailable. Please try again later.',
        AIConfigStatus.invalid =>
          'The AI API key appears to be invalid. Please ask an administrator to verify the configuration.',
        AIConfigStatus.checking => 'Checking AI configuration...',
      };

  bool get isUsable => this == AIConfigStatus.active;
}
