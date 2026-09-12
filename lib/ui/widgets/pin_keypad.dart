import 'package:flutter/material.dart';

/// A reusable, touch-friendly numeric keypad styled like a modern
/// phone lock screen.
///
/// Digits 1–9 and 0 render as large circular keys with dial-style
/// letter hints under 2–9. Backspace is a ghost circle that only
/// shows a fill while pressed. When [onNextPressed] is provided, the
/// bottom-left slot hosts a check key that lights up in primary when
/// [nextEnabled] is true — used by the set-PIN flow where the digit
/// count is variable.
///
/// The keypad does not manage any state — it simply notifies the
/// parent via [onDigitPressed], [onBackspacePressed], and
/// [onNextPressed].
class PinKeypad extends StatelessWidget {
  /// Called when a digit (0–9) is tapped.
  final ValueChanged<String> onDigitPressed;

  /// Called when the backspace button is tapped.
  final VoidCallback onBackspacePressed;

  /// Called when the check/next key is tapped. When null, the
  /// bottom-left slot stays empty (PIN lock behavior).
  final VoidCallback? onNextPressed;

  /// Whether the check/next key is active. Only meaningful when
  /// [onNextPressed] is provided.
  final bool nextEnabled;

  /// Whether input is currently disabled (e.g. during verification).
  final bool enabled;

  const PinKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onBackspacePressed,
    this.onNextPressed,
    this.nextEnabled = false,
    this.enabled = true,
  });

  static const Map<String, String> _letters = {
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(context, const ['1', '2', '3']),
        const SizedBox(height: 12),
        _buildRow(context, const ['4', '5', '6']),
        const SizedBox(height: 12),
        _buildRow(context, const ['7', '8', '9']),
        const SizedBox(height: 12),
        _buildRow(context, const [null, '0', 'backspace']),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<String?> items) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        if (item == null) {
          if (onNextPressed == null) {
            return const SizedBox(width: 80, height: 80);
          }
          return _IconKey(
            icon: Icons.check_rounded,
            semanticLabel: 'Continue',
            accent: nextEnabled,
            onTap: enabled && nextEnabled ? onNextPressed : null,
          );
        }
        if (item == 'backspace') {
          return _IconKey(
            icon: Icons.backspace_outlined,
            semanticLabel: 'Backspace',
            ghost: true,
            onTap: enabled ? onBackspacePressed : null,
          );
        }
        return _DigitKey(
          digit: item,
          letters: _letters[item],
          onTap: enabled ? () => onDigitPressed(item) : null,
        );
      }).toList(),
    );
  }
}

/// Circular digit key with an optional letter hint, mirroring a
/// phone dial pad. While held, the circle fills with the primary
/// color and scales down slightly.
class _DigitKey extends StatefulWidget {
  final String digit;
  final String? letters;
  final VoidCallback? onTap;

  const _DigitKey({required this.digit, this.letters, this.onTap});

  @override
  State<_DigitKey> createState() => _DigitKeyState();
}

class _DigitKeyState extends State<_DigitKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tappable = widget.onTap != null;
    final fg = _pressed ? cs.onPrimary : cs.onSurface;

    return Semantics(
      label: 'Digit ${widget.digit}',
      button: true,
      enabled: tappable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: tappable ? (_) => _setPressed(true) : null,
        onTapUp: tappable
            ? (_) {
                _setPressed(false);
                widget.onTap!();
              }
            : null,
        onTapCancel: tappable ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _pressed ? cs.primary : cs.surfaceContainerHigh,
              border: Border.all(
                color: _pressed ? cs.primary : cs.outline,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.digit,
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: fg,
                  ),
                ),
                if (widget.letters != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.letters!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      height: 1,
                      color: _pressed
                          ? cs.onPrimary.withValues(alpha: 0.78)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon-only circular key. In [ghost] mode the circle is transparent
/// until pressed (backspace). In accent mode a primary ring marks the
/// key as the active "continue" action (set-PIN check key).
class _IconKey extends StatefulWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool ghost;
  final bool accent;

  const _IconKey({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.ghost = false,
    this.accent = false,
  });

  @override
  State<_IconKey> createState() => _IconKeyState();
}

class _IconKeyState extends State<_IconKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tappable = widget.onTap != null;

    final Color bg;
    final Color fg;
    final Color? borderColor;
    if (widget.accent) {
      bg = _pressed ? cs.primary : Colors.transparent;
      fg = _pressed ? cs.onPrimary : cs.primary;
      borderColor = cs.primary;
    } else {
      bg = _pressed ? cs.surfaceContainerHigh : Colors.transparent;
      fg = tappable ? cs.onSurfaceVariant : cs.outlineVariant;
      borderColor = null;
    }

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: tappable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: tappable ? (_) => _setPressed(true) : null,
        onTapUp: tappable
            ? (_) {
                _setPressed(false);
                widget.onTap!();
              }
            : null,
        onTapCancel: tappable ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 26, color: fg),
          ),
        ),
      ),
    );
  }
}
