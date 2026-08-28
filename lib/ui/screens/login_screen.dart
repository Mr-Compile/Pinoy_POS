import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/theme_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _passwordFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      // Focus the first invalid field
      if (_usernameController.text.trim().isEmpty) {
        _usernameFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    final result = await authNotifier.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    switch (result) {
      case LoginResult.success:
        // Navigate based on the session phase.
        final phase = ref.read(authStateProvider).phase;
        if (phase != AuthSessionPhase.unauthenticated) {
          await AuthPhaseNavigator.pushReplacement(context, phase);
        }
      case LoginResult.invalidCredentials:
        await AppDialogService.error(
          context,
          title: 'Login Failed',
          message: 'Username or password is incorrect.',
        );
      case LoginResult.inactiveAccount:
        await AppDialogService.error(
          context,
          title: 'Account Unavailable',
          message: 'Your account is currently inactive. Please contact an administrator.',
        );
      case LoginResult.error:
        await AppDialogService.error(
          context,
          title: 'Sign In Error',
          message: 'Unable to sign in right now. Please try again.',
        );
    }
  }

  void _cycleTheme() {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentMode = ref.read(themeProvider).themeMode;
    // Cycle: system → light → dark → system
    final nextMode = switch (currentMode) {
      'system' => 'light',
      'light' => 'dark',
      _ => 'system',
    };
    themeNotifier.setThemeMode(nextMode);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final themeState = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    // Logo size scales with screen width but is capped
    final logoSize = isTablet ? 100.0 : 80.0;

    // Theme icon based on current mode
    final (themeIcon, themeLabel) = switch (themeState.themeMode) {
      'system' => (Icons.brightness_auto_outlined, 'System'),
      'light' => (Icons.light_mode_outlined, 'Light'),
      _ => (Icons.dark_mode_outlined, 'Dark'),
    };

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // ── Main login content ──
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 48 : 24,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── Logo ──
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: logoSize,
                                  maxHeight: logoSize * 1.25,
                                ),
                                child: AppLogo(
                                  size: logoSize,
                                  variant: LogoVariant.full,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // ── App name ──
                              Text(
                                AppConstants.appName,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              // ── Tagline ──
                              Text(
                                'Simple. Offline. Reliable.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 32),

                              // ── Username field ──
                              TextFormField(
                                controller: _usernameController,
                                focusNode: _usernameFocus,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(),
                                ),
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter your username';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  FocusScope.of(context).requestFocus(_passwordFocus);
                                },
                              ),
                              const SizedBox(height: 16),

                              // ── Password field ──
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter your password';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 28),

                              // ── Login button ──
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton(
                                  onPressed: authState.isLoading ? null : _login,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: authState.isLoading
                                      ? const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text('Signing in...'),
                                          ],
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Theme toggle (top-right) ──
              Positioned(
                top: 8,
                right: 8,
                child: Semantics(
                  label: 'Change theme. Current: $themeLabel',
                  button: true,
                  child: Tooltip(
                    message: 'Theme: $themeLabel. Tap to change.',
                    child: IconButton(
                      onPressed: _cycleTheme,
                      icon: Icon(themeIcon),
                      iconSize: 24,
                      tooltip: 'Change theme',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
