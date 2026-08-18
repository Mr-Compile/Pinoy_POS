import 'package:flutter/material.dart';

enum AuthMode { password, pin }

class AuthModeSwitcher extends StatelessWidget {
  final AuthMode currentMode;
  final ValueChanged<AuthMode> onModeChanged;

  const AuthModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SegmentedButton<AuthMode>(
      segments: const [
        ButtonSegment(
          value: AuthMode.password,
          icon: Icon(Icons.lock_outline, size: 18),
          label: Text('Password'),
        ),
        ButtonSegment(
          value: AuthMode.pin,
          icon: Icon(Icons.dialpad, size: 18),
          label: Text('PIN'),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (selection) => onModeChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return null;
        }),
      ),
    );
  }
}
