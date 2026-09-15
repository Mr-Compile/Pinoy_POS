import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/dialogs/developer_access_dialog.dart';
import 'package:pinoy_pos/ui/screens/developer_license_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Full-screen block shown while the developer license lock is engaged.
///
/// Replaces the entire navigation stack, so every user on the device is
/// locked out regardless of role or session. Exits only when
/// [LicenseStatus.isLocked] becomes false — via an unlock code dictated by
/// the developer, or the developer opening the hidden panel from here.
///
/// Information hierarchy: lock state → contact → unlock code → developer
/// access (tertiary).
class LicenseLockedScreen extends ConsumerStatefulWidget {
  const LicenseLockedScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const LicenseLockedScreen());

  @override
  ConsumerState<LicenseLockedScreen> createState() =>
      _LicenseLockedScreenState();
}

class _LicenseLockedScreenState extends ConsumerState<LicenseLockedScreen> {
  final _codeController = TextEditingController();
  bool _redeeming = false;
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
    final error = AppSemanticColors.resolve(AppSemanticColors.error, brightness);

    // Self-healing exit: the moment the license is no longer locked (code
    // redeemed, or the developer disarmed it in the panel pushed on top of
    // this screen) route to login and clear the stack.
    if (!status.isLocked && !status.isEvaluating && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      });
    }

    final isTampered = status.state == LicenseLockState.tampered;
    final headline = isTampered
        ? 'System Check Failed'
        : status.isTrial
            ? 'Trial Ended'
            : 'System Locked';
    final message = isTampered
        ? 'This installation could not verify its license state. '
            'Please contact the developer.'
        : (status.message.isNotEmpty
            ? status.message
            : status.isTrial
                ? LicenseService.trialLockMessage
                : LicenseService.defaultLockMessage);

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
                    // ── Lock badge ──
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: error.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isTampered
                              ? Icons.gpp_bad_outlined
                              : Icons.lock_outline,
                          size: 44,
                          color: error,
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),

                    Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineSmallBold(context),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      message,
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

                    // ── Unlock code ──
                    AppTextFormField(
                      controller: _codeController,
                      label: 'Unlock code',
                      hint: 'XXXX-XXXX',
                      prefixIcon: Icons.key_outlined,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9A-Za-z-]'),
                        ),
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _redeem(),
                    ),
                    const SizedBox(height: Spacing.md),
                    AppButton.gradient(
                      label: 'Unlock',
                      icon: Icons.lock_open_outlined,
                      fullWidth: true,
                      isLoading: _redeeming,
                      onPressed: _redeem,
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

  Future<void> _redeem() async {
    final input = _codeController.text.trim();
    if (input.isEmpty || _redeeming) return;

    setState(() => _redeeming = true);
    try {
      final result =
          await ref.read(licenseServiceProvider).redeemUnlockCode(input);
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
          title: result.alreadyUsed ? 'Code Already Used' : 'Invalid Code',
          message: result.alreadyUsed
              ? 'This code has already been used on this device.'
              : 'The unlock code is not valid. Check the code and try again.',
        );
        return;
      }

      await AppDialogService.success(
        context,
        title: 'Unlocked',
        message:
            'License extended by ${result.daysGranted} days until '
            '${DateFormat('MMM d, yyyy').format(result.newExpiry!)}.',
      );
      await ref.read(licenseStatusProvider.notifier).refresh();
      // The build watcher routes to the login screen once the provider
      // reports an unlocked state.
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

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
