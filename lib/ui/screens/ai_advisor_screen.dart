import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

class AIAdvisorScreen extends StatelessWidget {
  const AIAdvisorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Business Advisor'),
      ),
      body: const EmptyState(
        icon: Icons.psychology,
        title: 'AI Advisor',
        message: 'AI-powered business insights coming soon',
      ),
    );
  }
}
