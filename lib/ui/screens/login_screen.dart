import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/dialogs/license_unlock_dialog.dart';
import 'package:pinoy_pos/ui/screens/license_locked_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_logo.dart';
import 'package:pinoy_pos/ui/widgets/developer_access_gate.dart';
import 'package:pinoy_pos/ui/widgets/license_countdown_chip.dart';
import 'package:pinoy_pos/ui/widgets/license_expiry_banner.dart';
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

  /// Prevents the self-healing redirect in [build] from scheduling more
  /// than one navigation.
  bool _hasNavigated = false;

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

  /// Pre-expiry code redemption — a client holding a code can extend the
  /// license before it locks, straight from the sign-in screen.
  Future<void> _enterUnlockCode() async {
    final result = await showLicenseUnlockDialog(
      context,
      ref.read(licenseServiceProvider),
    );
    if (result == null || !mounted) return;

    await ref.read(licenseStatusProvider.notifier).refresh();
    if (!mounted) return;
    await AppDialogService.success(
      context,
      title: 'License Extended',
      message:
          'The license now runs until '
          '${DateFormat('MMM d, yyyy').format(result.newExpiry!)}.',
    );
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    // A locked license blocks login entirely — route to the lock screen.
    if (ref.read(licenseStatusProvider).isLocked) {
      await Navigator.of(context).pushAndRemoveUntil(
        LicenseLockedScreen.route(),
        (_) => false,
      );
      return;
    }

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
        // The auth notifier has already settled user + phase by this
        // point (state assignment is synchronous inside login()), so the
        // phase read here is authoritative — no delay or retry needed.
        final phase = ref.read(authStateProvider).phase;
        if (phase != AuthSessionPhase.unauthenticated) {
          // Clear the whole stack so the system back button can never
          // return to this screen or to a previous user's dashboard.
          _hasNavigated = true;
          await AuthPhaseNavigator.pushAndRemoveUntil(context, phase);
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
    final licenseStatus = ref.watch(licenseStatusProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    // Self-healing redirect: if this screen is ever built while a session
    // is already active — for example a stale login route resurfacing via
    // the back stack or a transition race — route to the screen the
    // current phase requires instead of showing the sign-in form.
    if (!authState.isLoading &&
        authState.phase != AuthSessionPhase.unauthenticated &&
        !_hasNavigated) {
      _hasNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(authStateProvider);
        if (current.isLoading ||
            current.phase == AuthSessionPhase.unauthenticated) {
          // The session ended between scheduling and firing; stay here.
          _hasNavigated = false;
          return;
        }
        AuthPhaseNavigator.pushAndRemoveUntil(context, current.phase);
      });
    }

    final isDark = brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide =
                  layoutClassFor(constraints.maxWidth).isAtLeastMedium;
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
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: isDark ? 0.18 : 0.10,
                                ),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
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
                                  DeveloperAccessGate(
                                    child: _IconContainer(
                                      size: iconContainerSize,
                                      iconSize: iconSize,
                                      isDark: isDark,
                                    ),
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
                                  if (licenseStatus.isExpiringSoon) ...[
                                    const SizedBox(height: 20),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.card),
                                      child: const LicenseExpiryBanner(),
                                    ),
                                  ] else if (licenseStatus.showCountdown) ...[
                                    const SizedBox(height: 20),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.card),
                                      child: const LicenseCountdownChip(),
                                    ),
                                  ],
                                  const SizedBox(height: 40),
                                  _buildUsernameField(),
                                  const SizedBox(height: 16),
                                  _buildPasswordField(authState.isLoading),
                                  const SizedBox(height: 32),
                                  AppButton.gradient(
                    label: 'Sign In',
                    onPressed: _login,
                    isLoading: authState.isLoading,
                    fullWidth: true,
                  ),
                                  if (licenseStatus.state ==
                                      LicenseLockState.active) ...[
                                    const SizedBox(height: 8),
                                    AppButton.text(
                                      label: 'Have an unlock code?',
                                      size: AppButtonSize.small,
                                      color: AppButtonColor.neutral,
                                      onPressed: _enterUnlockCode,
                                    ),
                                  ],
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

  Widget _buildUsernameField() {
    return AppTextFormField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      hint: 'Username',
      prefixIcon: Icons.person_outline,
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

  Widget _buildPasswordField(bool isLoading) {
    return AppPasswordField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      label: null,
      hint: 'Password',
      prefixIcon: Icons.lock_outline,
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
        color: isDark
            ? AppColorTokens.darkSurfaceElevated
            : AppColorTokens.lightSurfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
            blurRadius: 24,
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
