import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/pin_indicators.dart';
import 'package:pinoy_pos/ui/widgets/pin_keypad.dart';

/// PIN Lock screen — shown after successful password login when the
/// user has a PIN configured.
///
/// Features:
/// - Displays the user's avatar, full name, and "Enter your PIN" prompt.
/// - Dynamic PIN length detection (4–6 dots based on configured PIN).
/// - On-screen numeric keypad with backspace.
/// - Auto-submit when the required number of digits is entered.
/// - Auto-submit locking to prevent duplicate verification.
/// - Error dialog on incorrect PIN, then clears input.
/// - "Back to Login" action that clears the session and returns to
///   the login screen.
/// - Android system back button is intercepted to prevent bypassing
///   the PIN lock.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _enteredPin = '';
  bool _isVerifying = false;
  bool _hasError = false;
  ProviderSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual<AuthState>(
      authStateProvider,
      (previous, next) {
        // Only react to actual phase transitions.
        if (previous?.phase == next.phase) return;

        // When phase becomes fullyAuthenticated, navigate to AppShell.
        // When phase becomes unauthenticated (e.g. cancelPinFlow),
        // navigate to LoginScreen.
        if (next.phase == AuthSessionPhase.fullyAuthenticated ||
            next.phase == AuthSessionPhase.unauthenticated) {
          AuthPhaseNavigator.pushAndRemoveUntil(context, next.phase);
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _authSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: cs.primary),
        ),
      );
    }

    final pinLength = user.configuredPinLength > 0
        ? user.configuredPinLength
        : 4;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack(context);
        }
      },
      child: Scaffold(
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
                    // ── Profile avatar ──
                    AppAvatar(
                      imagePath: user.profileImagePath,
                      initials: user.fullName,
                      radius: 40,
                      semanticLabel: 'Profile picture of ${user.fullName}',
                    ),
                    const SizedBox(height: 16),

                    // ── Full name ──
                    Text(
                      user.fullName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),

                    // ── Username ──
                    Text(
                      '@${user.username}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── "Enter your PIN" prompt ──
                    Text(
                      'Enter your PIN',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── PIN indicators ──
                    PinIndicators(
                      pinLength: pinLength,
                      enteredCount: _enteredPin.length,
                      error: _hasError,
                    ),
                    const SizedBox(height: 32),

                    // ── Numeric keypad ──
                    PinKeypad(
                      onDigitPressed: (digit) => _onDigitPressed(
                        digit,
                        pinLength,
                      ),
                      onBackspacePressed: _onBackspace,
                      enabled: !_isVerifying,
                    ),
                    const SizedBox(height: 24),

                    // ── Back to Login ──
                    TextButton.icon(
                      onPressed: _isVerifying
                          ? null
                          : () => _handleBack(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppSemanticColors.resolve(
                          AppSemanticColors.error,
                          Theme.of(context).brightness,
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Back to Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── INPUT HANDLING ──────────────────────────────────────────────────

  void _onDigitPressed(String digit, int pinLength) {
    if (_isVerifying) return;
    if (_enteredPin.length >= pinLength) return;

    setState(() {
      _hasError = false;
      _enteredPin += digit;
    });

    if (_enteredPin.length == pinLength) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_isVerifying) return;
    if (_enteredPin.isEmpty) return;

    setState(() {
      _hasError = false;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  // ── PIN VERIFICATION ────────────────────────────────────────────────

  Future<void> _verifyPin() async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _hasError = false;
    });

    final result = await ref.read(authStateProvider.notifier).verifyPin(
          _enteredPin,
        );

    if (!mounted) return;

    switch (result) {
      case PinVerifyResult.success:
        // Phase transitions to fullyAuthenticated; navigation is
        // handled by the routing layer (SplashScreen / AppShell).
        break;
      case PinVerifyResult.incorrect:
        setState(() {
          _hasError = true;
          _isVerifying = false;
          _enteredPin = '';
        });
        await AppDialogService.error(
          context,
          title: 'Incorrect PIN',
          message: 'The PIN you entered is incorrect. Please try again.',
        );
      case PinVerifyResult.inactive:
        setState(() {
          _isVerifying = false;
          _enteredPin = '';
        });
        await AppDialogService.error(
          context,
          title: 'Account Unavailable',
          message:
              'Your account is currently inactive. Please contact an administrator.',
        );
        if (!mounted) return;
        await _handleBack(context);
      case PinVerifyResult.userDeleted:
        setState(() {
          _isVerifying = false;
          _enteredPin = '';
        });
        await AppDialogService.error(
          context,
          title: 'Account Deleted',
          message: 'This account has been deleted. Please contact an administrator.',
        );
        if (!mounted) return;
        await _handleBack(context);
      case PinVerifyResult.noPin:
        // PIN was removed while the lock screen was open — this
        // shouldn't happen in normal flow, but we handle it by
        // cancelling back to login.
        setState(() {
          _isVerifying = false;
          _enteredPin = '';
        });
        await _handleBack(context);
      case PinVerifyResult.noSession:
      case PinVerifyResult.userNotFound:
        setState(() {
          _isVerifying = false;
          _enteredPin = '';
        });
        await AppDialogService.error(
          context,
          title: 'Session Error',
          message: 'Your session could not be verified. Please log in again.',
        );
        if (!mounted) return;
        await _handleBack(context);
    }
  }

  // ── BACK TO LOGIN ───────────────────────────────────────────────────

  Future<void> _handleBack(BuildContext context) async {
    if (_isVerifying) return;

    await ref.read(authStateProvider.notifier).cancelPinFlow();
  }
}
