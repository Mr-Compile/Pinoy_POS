import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash Bin'),
      ),
      body: const EmptyState(
        icon: Icons.delete_outline,
        title: 'Trash Bin',
        message: 'Deleted items will appear here for recovery',
      ),
    );
  }
}
