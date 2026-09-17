import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice-input wrapper around [stt.SpeechToText] for the AI chat.
///
/// The mic button uses this service to stream partial speech results into
/// the chat text field — the user speaks, watches the words appear, then
/// taps send like a normal typed message (dictation never auto-sends, so a
/// misheard phrase can't burn an AI query).
///
/// Platform coverage: Android, iOS, macOS, Windows (via
/// speech_to_text_windows), and web. On platforms without a speech
/// implementation [isSupported] is false and the UI hides the mic button.
class VoiceInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;

  /// Whether the current platform has a speech-recognition implementation.
  /// Checked before attempting [initialize] so unsupported platforms never
  /// touch the plugin.
  static bool get platformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;

  /// Initializes the speech engine once and requests the microphone /
  /// speech permissions where the platform requires it. Returns false when
  /// speech is unavailable or permission was denied.
  Future<bool> initialize() async {
    if (_initialized) return _available;
    if (!platformSupported) {
      _initialized = true;
      _available = false;
      return false;
    }
    try {
      _available = await _speech.initialize(
        onError: (e) => _log('speech error: ${e.errorMsg}'),
      );
    } catch (e, st) {
      _log('initialize failed: $e\n$st');
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  /// Starts a listening session. [onWords] receives the latest recognized
  /// text (partial and final); [onDone] fires when the session ends —
  /// either by user stop, silence timeout, or error.
  Future<void> start({
    required void Function(String words) onWords,
    void Function()? onDone,
  }) async {
    if (!await initialize()) {
      onDone?.call();
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) => onWords(result.recognizedWords),
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 6),
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      // Poll for the session ending so [onDone] fires on silence timeout.
      _watchForEnd(onDone);
    } catch (e, st) {
      _log('listen failed: $e\n$st');
      onDone?.call();
    }
  }

  void _watchForEnd(void Function()? onDone) {
    if (onDone == null) return;
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 300));
      return _speech.isListening;
    }).whenComplete(onDone);
  }

  /// Stops the current session, keeping the last recognized words.
  Future<void> stop() async {
    if (!_speech.isListening) return;
    try {
      await _speech.stop();
    } catch (e, st) {
      _log('stop failed: $e\n$st');
    }
  }

  /// Cancels the session, discarding pending results.
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (e, st) {
      _log('cancel failed: $e\n$st');
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[VoiceInputService] $message');
    }
  }
}
