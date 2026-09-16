import 'package:flutter/material.dart';

class ErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onPrimaryAction;
  final String? primaryActionLabel;

  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.onPrimaryAction,
    this.primaryActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final primary = onPrimaryAction ?? onRetry;
    final primaryLabel = primaryActionLabel ?? 'Retry';
    final primaryIcon = onPrimaryAction != null ? null : const Icon(Icons.refresh);

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (primary != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: primary,
                  icon: primaryIcon,
                  label: Text(primaryLabel),
                ),
              ],
            ],
          ),
        );

        if (!constraints.hasBoundedHeight) {
          return Center(child: content);
        }

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              // Match EmptyState: fill available width so content stays
              // centered instead of shrink-wrapping to the left edge.
              minWidth:
                  constraints.hasBoundedWidth ? constraints.maxWidth : 0.0,
            ),
            child: content,
          ),
        );
      },
    );
  }
}
