import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/password_strength_meter.dart';
import 'package:pinoy_pos/ui/widgets/password_requirements_checklist.dart';

/// Full-screen forced password change.
///
/// Displayed when the user logs in with a temporary password
/// (`mustChangePassword == true`).  The user cannot dismiss this screen
/// or access any protected route until the password is successfully
/// changed.
///
/// The only escape action is "Sign Out" which returns to the login
/// screen.
class ForceChangePasswordScreen extends ConsumerStatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  ConsumerState<ForceChangePasswordScreen> createState() =>
      _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState
    extends ConsumerState<ForceChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  bool _newPasswordTouched = false;
  bool _confirmPasswordTouched = false;
  ProviderSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual(
      authStateProvider,
      (previous, next) {
        // Only react to actual phase transitions. Without this guard a
        // rebuild of the auth state can re-trigger the same navigation,
        // which may lead to framework assertion failures when the old
        // route is removed more than once.
        if (previous?.phase == next.phase) return;

        if (next.phase == AuthSessionPhase.fullyAuthenticated ||
            next.phase == AuthSessionPhase.passwordAuthenticatedPendingPin ||
            next.phase == AuthSessionPhase.unauthenticated) {
          AuthPhaseNavigator.pushAndRemoveUntil(context, next.phase);
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    // Force validation on all fields.
    setState(() {
      _newPasswordTouched = true;
      _confirmPasswordTouched = true;
    });
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    final result = await ref
        .read(authStateProvider.notifier)
        .changePassword(newPassword: _newPasswordController.text);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      await AppDialogService.success(
        context,
        title: 'Password Changed',
        message: 'Your password has been changed successfully.',
      );
    } else {
      await AppDialogService.error(
        context,
        title: 'Change Failed',
        message: result.message,
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        iconColor: AppSemanticColors.error,
        title: const Text('Sign Out?'),
        content: const Text(
          'You will need to log in again with your temporary password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.error,
              foregroundColor: AppSemanticColors.onError,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authStateProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final maxWidth = isTablet ? 480.0 : double.infinity;

    final password = _newPasswordController.text;
    final strengthResult = PasswordStrengthService.evaluate(
      password: password,
      username: ref.read(authStateProvider).user?.username,
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.lock_person_outlined,
                        size: 64,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Create a new password',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'For your security, you need to change the temporary password before continuing.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(() =>
                                _obscureNewPassword = !_obscureNewPassword),
                            tooltip: _obscureNewPassword
                                ? 'Show password'
                                : 'Hide password',
                          ),
                        ),
                        obscureText: _obscureNewPassword,
                        textInputAction: TextInputAction.next,
                        onChanged: (value) {
                          setState(() {
                            _newPasswordTouched = true;
                          });
                        },
                        validator: (value) {
                          if (!_newPasswordTouched) return null;
                          if (value == null || value.isEmpty) {
                            return 'Enter a password.';
                          }
                          final error = PasswordStrengthService.validate(
                            password: value,
                            username: ref
                                .read(authStateProvider)
                                .user
                                ?.username,
                          );
                          return error;
                        },
                      ),
                      const SizedBox(height: 12),
                      if (password.isNotEmpty)
                        PasswordStrengthMeter(result: strengthResult),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                            tooltip: _obscureConfirmPassword
                                ? 'Show password'
                                : 'Hide password',
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onChanged: (value) {
                          setState(() {
                            _confirmPasswordTouched = true;
                          });
                        },
                        validator: (value) {
                          if (!_confirmPasswordTouched) return null;
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password.';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Your passwords don\'t match.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleSubmit(),
                      ),
                      const SizedBox(height: 20),
                      PasswordRequirementsChecklist(result: strengthResult),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                        ),
                        child: _isSubmitting
                            ? SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Text(
                                'Continue',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isSubmitting ? null : _handleSignOut,
                        style: TextButton.styleFrom(
                          foregroundColor: AppSemanticColors.error,
                        ),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
