import 'package:flutter/material.dart';

void showErrorSnackbar(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error, color: colorScheme.onError),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: colorScheme.error,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
