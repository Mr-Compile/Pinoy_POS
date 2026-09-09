import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_circle.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppHeader(
        title: 'Access Denied',
        showBackButton: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'Access denied',
                child: AppIconCircle.fullscreen(
                  icon: Icons.lock,
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  iconColor: colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: AppTypography.titleLargeBold(context),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have permission to access this page.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              AppButton.filled(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icons.arrow_back,
                label: 'Go Back',
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
