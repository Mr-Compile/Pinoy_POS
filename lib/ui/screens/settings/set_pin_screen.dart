import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/pin_indicators.dart';
import 'package:pinoy_pos/ui/widgets/pin_keypad.dart';

/// Set PIN screen — replaces the old two-field dialog with a
/// modern phone-style two-step create/confirm flow.
///
/// Step 1 — Create: the user types 4–6 digits. Dots grow as they
/// type (variable length, no fixed slots) and a check key in the
/// bottom-left slot of the keypad lights up once 4 digits are in.
///
/// Step 2 — Confirm: the user re-enters the same PIN. On a match the
/// PIN is saved, the dots flash success green, and the standard
/// success dialog confirms before popping back. On a mismatch the
/// dots shake red, an inline hint explains the failure, and the
/// flow restarts at step 1.
///
/// Reached from Settings → PIN → Set / Change PIN.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  static const int minPinLength = 4;
  static const int maxPinLength = 6;

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  int _step = 1;
  String _entry = '';
  String _pin = '';
  bool _mismatch = false;
  bool _saving = false;
  bool _saved = false;
  final GlobalKey<PinIndicatorsState> _dotsKey =
      GlobalKey<PinIndicatorsState>();

  bool get _inputLocked => _saving || _saved;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isTablet =
        layoutClassFor(MediaQuery.of(context).size.width).isAtLeastMedium;

    if (user == null) {
      return Scaffold(
        appBar: const AppHeader(title: 'Set PIN', showBackButton: true),
        body: Center(
          child: CircularProgressIndicator(color: cs.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'Set PIN',
        subtitle: _step == 1
            ? 'Step 1 of 2 — Create'
            : 'Step 2 of 2 — Confirm',
        showBackButton: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 48 : 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── PIN icon badge ──
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainerHigh,
                      border: Border.all(color: cs.outline, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.pin_outlined,
                      size: 30,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Step prompt ──
                  Text(
                    _step == 1 ? 'Create your PIN' : 'Confirm your PIN',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // ── Hint / mismatch message ──
                  if (_mismatch)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 15,
                          color: cs.error,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'PINs didn\'t match — start over',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      _step == 1
                          ? 'Use ${SetPinScreen.minPinLength}–'
                              '${SetPinScreen.maxPinLength} digits, '
                              'then tap ✓'
                          : 'Re-enter the same PIN',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 18),

                  // ── Dots — grow as the user types ──
                  SizedBox(
                    height: 15,
                    child: PinIndicators(
                      key: _dotsKey,
                      pinLength: _entry.length,
                      enteredCount: _entry.length,
                      error: _mismatch,
                      success: _saved,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ── Circular keypad with check key ──
                  PinKeypad(
                    onDigitPressed: _onDigitPressed,
                    onBackspacePressed: _onBackspace,
                    onNextPressed: _onNext,
                    nextEnabled:
                        _entry.length >= SetPinScreen.minPinLength &&
                            !_inputLocked,
                    enabled: !_inputLocked,
                  ),
                  const SizedBox(height: 16),

                  // ── Cancel ──
                  TextButton(
                    onPressed:
                        _inputLocked ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── INPUT HANDLING ──────────────────────────────────────────────────

  void _onDigitPressed(String digit) {
    if (_inputLocked) return;
    if (_mismatch) return;
    if (_entry.length >= SetPinScreen.maxPinLength) return;
    setState(() => _entry += digit);
  }

  void _onBackspace() {
    if (_inputLocked || _mismatch || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _onNext() {
    if (_inputLocked || _entry.length < SetPinScreen.minPinLength) {
      return;
    }

    if (_step == 1) {
      setState(() {
        _pin = _entry;
        _entry = '';
        _step = 2;
      });
      return;
    }

    if (_entry == _pin) {
      _savePin();
    } else {
      _handleMismatch();
    }
  }

  // ── MISMATCH ────────────────────────────────────────────────────────

  Future<void> _handleMismatch() async {
    setState(() => _mismatch = true);
    _dotsKey.currentState?.shake();
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _step = 1;
      _entry = '';
      _pin = '';
      _mismatch = false;
    });
  }

  // ── SAVE ────────────────────────────────────────────────────────────

  Future<void> _savePin() async {
    final user = ref.read(authStateProvider).user;
    if (user == null || user.id == null) return;

    setState(() => _saving = true);

    final success = await ref.read(authStateProvider.notifier).updateProfile(
          userId: user.id!,
          fullName: user.fullName,
          pin: _pin,
        );

    if (!mounted) return;

    if (!success) {
      setState(() => _saving = false);
      await AppDialogService.error(
        context,
        title: 'Update Failed',
        message: 'Failed to update PIN.',
      );
      return;
    }

    // Flash the success dots before the confirmation dialog.
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    await AppDialogService.success(
      context,
      title: 'PIN Updated',
      message: 'Your PIN has been set successfully.',
    );
    if (!mounted) return;
    Navigator.pop(context);
  }
}
