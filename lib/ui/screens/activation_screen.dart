import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/ui/dialogs/developer_access_dialog.dart';
import 'package:pinoy_pos/ui/screens/developer_license_screen.dart';
import 'package:pinoy_pos/ui/screens/license_locked_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Full-screen gate shown while the install has never been activated —
/// fresh installs and devices whose app storage was wiped.
///
/// Replaces the entire navigation stack, so no user on the device can
/// reach the app until the developer's master activation code is entered.
/// Exits the moment [LicenseStatus.requiresActivation] becomes false —
/// to the license lock screen if the resolved state is locked, otherwise
/// to login.
///
/// Information hierarchy: activation state → contact → code entry →
/// developer access (tertiary).
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const ActivationScreen());

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _codeController = TextEditingController();
  bool _activating = false;
  bool _navigated = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider);
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final accent = AppSemanticColors.resolve(
      AppSemanticColors.warning,
      brightness,
    );

    // Self-healing exit: the moment the device is activated, route onward
    // and clear the stack. An armed-then-wiped device can resolve straight
    // into a locked state, so the destination is picked from the status
    // rather than assumed to be login.
    if (!status.requiresActivation && !status.isEvaluating && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(licenseStatusProvider);
        Navigator.of(context).pushAndRemoveUntil(
          current.isLocked
              ? LicenseLockedScreen.route()
              : MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      });
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Activation badge ──
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 44,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),

                    Text(
                      'Activation Required',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineSmallBold(context),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'This installation must be activated before use. '
                      'Enter the activation code provided by the developer.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium(context)
                          .copyWith(color: cs.onSurfaceVariant),
                    ),

                    // ── Developer contact ──
                    if (status.contactInfo.isNotEmpty) ...[
                      const SizedBox(height: Spacing.md),
                      AppCard(
                        child: Row(
                          children: [
                            Icon(
                              Icons.contact_phone_outlined,
                              size: 20,
                              color: cs.primary,
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Contact the developer',
                                    style: AppTypography.labelMedium(context)
                                        .copyWith(color: cs.onSurfaceVariant),
                                  ),
                                  Text(
                                    status.contactInfo,
                                    style: AppTypography.bodyMediumSemibold(
                                        context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: Spacing.xl),
                    const Divider(),
                    const SizedBox(height: Spacing.lg),

                    // ── Activation code ──
                    AppTextFormField(
                      controller: _codeController,
                      label: 'Activation code',
                      hint: 'XXXX-XXXX',
                      prefixIcon: Icons.key_outlined,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9A-Za-z-]'),
                        ),
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _activate(),
                    ),
                    const SizedBox(height: Spacing.md),
                    AppButton.gradient(
                      label: 'Activate',
                      icon: Icons.verified_outlined,
                      fullWidth: true,
                      isLoading: _activating,
                      onPressed: _activate,
                    ),
                    const SizedBox(height: Spacing.md),

                    Center(
                      child: AppButton.text(
                        label: 'Developer access',
                        size: AppButtonSize.small,
                        color: AppButtonColor.neutral,
                        onPressed: _openDeveloperAccess,
                      ),
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

  Future<void> _activate() async {
    final input = _codeController.text.trim();
    if (input.isEmpty || _activating) return;

    setState(() => _activating = true);
    try {
      final result =
          await ref.read(licenseServiceProvider).redeemActivationCode(input);
      if (!mounted) return;

      if (result.retryAfter != null) {
        final minutes = result.retryAfter!.inMinutes + 1;
        await AppDialogService.error(
          context,
          title: 'Too Many Attempts',
          message: 'Try again in $minutes min.',
        );
        return;
      }

      if (!result.success) {
        await AppDialogService.error(
          context,
          title: 'Invalid Code',
          message:
              'The activation code is not valid. Check the code and try again.',
        );
        return;
      }

      await ref.read(licenseStatusProvider.notifier).refresh();
      // The build watcher routes onward once the provider reports the
      // device activated — no success dialog, the transition IS the
      // confirmation.
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  /// The panel is gated while the device is unactivated — this opens the
  /// access dialog, which reports that activation must happen first. Kept
  /// visible so the developer knows the panel exists but cannot use it to
  /// sidestep the code.
  Future<void> _openDeveloperAccess() async {
    final service = ref.read(licenseServiceProvider);
    final authorized = await showDeveloperAccessDialog(context, service);
    if (!authorized || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeveloperLicenseScreen()),
    );
    if (!mounted) return;
    await ref.read(licenseStatusProvider.notifier).refresh();
  }
}
