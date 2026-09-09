import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/ui/widgets/ai_chat_head.dart';
import 'package:pinoy_pos/ui/widgets/ai_chat_panel.dart';

/// Root-level overlay that keeps the AI chat head (and optional chat panel)
/// accessible from any authenticated screen.
///
/// The overlay is placed inside [MaterialApp.builder], so it floats above the
/// entire route stack. It only appears when:
/// - the session is [AuthSessionPhase.fullyAuthenticated],
/// - the current user has the `use_ai_advisor` permission, and
/// - the top route is not the full-screen [AIAdvisorScreen].
///
/// It hides the chat head while the AI panel is open and displays the panel
/// in that case.
class GlobalAIChatOverlay extends ConsumerWidget {
  const GlobalAIChatOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final chatState = ref.watch(aiAdvisorChatProvider);
    final currentRoute = ref.watch(currentRouteProvider);
    final user = authState.user;

    final canUse = user != null &&
        authState.phase == AuthSessionPhase.fullyAuthenticated &&
        ref.read(authStateProvider.notifier).hasPermission('use_ai_advisor');

    // The AI Advisor full-screen route is the one screen where the floating
    // chat head would be redundant.
    final isOnAiScreen =
        currentRoute == 'ai_advisor' || currentRoute == 'AIAdvisorScreen';

    if (!canUse) return child;

    return Stack(
      children: [
        child,
        if (!isOnAiScreen && !chatState.isPanelOpen)
          AIChatHead(userId: user.id!),
        if (!isOnAiScreen && chatState.isPanelOpen)
          const AIChatPanel(),
      ],
    );
  }
}
