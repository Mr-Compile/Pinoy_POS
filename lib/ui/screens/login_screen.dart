import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
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
                                  _buildSignInButton(authState.isLoading, colorScheme, brightness),
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
    final borderRadius = BorderRadius.circular(20);
    final hintStyle = AppTypography.bodyMedium(context)
        .copyWith(color: colorScheme.onSurfaceVariant);

    return TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      decoration: InputDecoration(
        hintText: 'Username',
        hintStyle: hintStyle,
        filled: true,
        prefixIcon: Icon(Icons.person_outline, color: colorScheme.primary),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
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
    );
  }

  Widget _buildPasswordField(ColorScheme colorScheme, bool isLoading) {
    final borderRadius = BorderRadius.circular(20);
    final hintStyle = AppTypography.bodyMedium(context)
        .copyWith(color: colorScheme.onSurfaceVariant);

    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: hintStyle,
        filled: true,
        prefixIcon: Icon(Icons.lock_outline, color: colorScheme.primary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: isLoading
              ? null
              : () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        ),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      autofillHints: const [AutofillHints.password],
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

  Widget _buildSignInButton(bool isLoading, ColorScheme colorScheme, Brightness brightness) {
    final gradientColors = [
      AppSemanticColors.resolve(AppSemanticColors.primaryLight, brightness),
      AppSemanticColors.resolve(AppSemanticColors.primaryDark, brightness),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: isLoading ? null : _login,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: gradientColors,
              ),
            ),
            child: Center(
              child: isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Signing in...',
                          style: AppTypography.titleMediumBold(context)
                              .copyWith(color: Colors.white),
                        ),
                      ],
                    )
                  : Text(
                      'Sign In',
                      style: AppTypography.titleMediumBold(context)
                          .copyWith(color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
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
