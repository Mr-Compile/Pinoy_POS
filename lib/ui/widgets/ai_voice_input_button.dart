import 'package:flutter/material.dart';

import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/services/voice_input_service.dart';

/// Microphone button for AI chat input bars.
///
/// Tap once to start dictation — recognized words stream into the bound
/// [controller] as partial results, so the user watches the message being
/// written. Tap again (or pause) to stop; the final text stays in the
/// field for review before the user taps send. Dictation never
/// auto-sends, so a misheard phrase can't consume an AI query.
///
/// Renders nothing on platforms without speech recognition, so callers
/// can drop it into any input bar unconditionally.
class AIVoiceInputButton extends StatefulWidget {
  const AIVoiceInputButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onListeningChanged,
  });

  /// The chat input field the recognized text is written into.
  final TextEditingController controller;

  /// Mirrors the send button's enabled state.
  final bool enabled;

  /// Fired when a listening session starts or ends — lets the parent
  /// adjust the input hint ("Listening…") or disable send.
  final ValueChanged<bool>? onListeningChanged;

  @override
  State<AIVoiceInputButton> createState() => AIVoiceInputButtonState();
}

class AIVoiceInputButtonState extends State<AIVoiceInputButton> {
  final VoiceInputService _voice = VoiceInputService();

  /// Text present before the current dictation session — recognized
  /// words are appended after it so separate utterances join cleanly.
  String _baseText = '';
  bool _listening = false;

  bool get isListening => _listening;

  Future<void> _toggle() async {
    if (_listening) {
      await stopListening();
      return;
    }
    _baseText = widget.controller.text;
    if (_baseText.isNotEmpty && !_baseText.endsWith(' ')) {
      _baseText = '$_baseText ';
    }
    _setListening(true);
    await _voice.start(
      onWords: (words) {
        if (!mounted) return;
        final combined = '$_baseText$words';
        widget.controller.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
      },
      onDone: () {
        if (mounted) _setListening(false);
      },
    );
    // start() returns early when speech is unavailable — reflect that.
    if (mounted && !_voice.isListening && _listening) {
      _setListening(false);
    }
  }

  /// Stops an active listening session, keeping the recognized text.
  /// Safe to call when not listening. Exposed so the parent can stop
  /// dictation before sending the message.
  Future<void> stopListening() async {
    if (!_listening) return;
    await _voice.stop();
    if (mounted) _setListening(false);
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    setState(() => _listening = value);
    widget.onListeningChanged?.call(value);
  }

  @override
  void dispose() {
    _voice.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!VoiceInputService.platformSupported) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.xs),
      child: IconButton(
        icon: Icon(
          _listening ? Icons.mic : Icons.mic_none,
          size: 20,
          color: _listening ? cs.onError : cs.onSurfaceVariant,
        ),
        style: IconButton.styleFrom(
          backgroundColor:
              _listening ? cs.error : cs.surfaceContainerHighest,
          side: _listening ? null : BorderSide(color: cs.outlineVariant),
        ),
        onPressed: widget.enabled ? _toggle : null,
        tooltip: _listening ? 'Stop voice input' : 'Voice input',
      ),
    );
  }
}
