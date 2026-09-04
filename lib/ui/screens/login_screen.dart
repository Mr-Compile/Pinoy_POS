import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_logo.dart';
import 'package:pinoy_pos/ui/widgets/theme_toggle.dart';

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
    FocusScope.of(context).unfocus();

    if (ref.read(authStateProvider).isLoading) return;

    if (!_formKey.currentState!.validate()) {
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              final horizontalPadding = isWide ? 48.0 : 16.0;
              final cardPadding = isWide ? 48.0 : 28.0;
              final iconContainerSize = isWide ? 112.0 : 92.0;
              final iconSize = isWide ? 76.0 : 60.0;

              return Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? colorScheme.primary.withValues(alpha: 0.10)
                                    : colorScheme.shadow.withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(cardPadding),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _IconContainer(
                                    size: iconContainerSize,
                                    iconSize: iconSize,
                                    isDark: isDark,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    AppConstants.appName,
                                    style: AppTypography.headlineSmallBold(context)
                                        .copyWith(color: colorScheme.onSurface),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Simple. Offline. Reliable.',
                                    style: AppTypography.bodyMedium(context)
                                        .copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 40),
                                  _buildUsernameField(colorScheme),
                                  const SizedBox(height: 16),
                                  _buildPasswordField(colorScheme, authState.isLoading),
                                  const SizedBox(height: 32),
                                  AppButton.gradient(
                    label: 'Sign In',
                    onPressed: _login,
                    isLoading: authState.isLoading,
                    fullWidth: true,
                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: ThemeToggle(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameField(ColorScheme colorScheme) {
    return AppTextFormField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      hint: 'Username',
      prefix: Icon(Icons.person_outline, color: colorScheme.primary),
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
    );
  }

  Widget _buildPasswordField(ColorScheme colorScheme, bool isLoading) {
    return AppPasswordField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      label: null,
      hint: 'Password',
      prefix: Icon(Icons.lock_outline, color: colorScheme.primary),
      autofillHints: const [AutofillHints.password],
      isLoading: isLoading,
      textInputAction: TextInputAction.done,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter your password';
        }
        return null;
      },
      onFieldSubmitted: isLoading ? null : (_) => _login(),
    );
  }

}

class _IconContainer extends StatelessWidget {
  final double size;
  final double iconSize;
  final bool isDark;

  const _IconContainer({
    required this.size,
    required this.iconSize,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.35 : 0.22),
            blurRadius: isDark ? 28 : 20,
            spreadRadius: isDark ? 2 : 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: AppIcon(
        size: iconSize,
        forceDark: isDark,
      ),
    );
  }
}
