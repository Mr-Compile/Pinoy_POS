import 'package:flutter/material.dart';

mixin FormValidationMixin<T extends StatefulWidget> on State<T> {
  final Map<GlobalKey<FormFieldState>, FocusNode> _focusNodes = {};

  FocusNode getOrCreateFocusNode(GlobalKey<FormFieldState> formFieldKey) {
    return _focusNodes.putIfAbsent(formFieldKey, () => FocusNode());
  }

  bool validateAndScrollToError(GlobalKey<FormState> formKey) {
    if (!formKey.currentState!.validate()) {
      _scrollToFirstError(formKey);
      return false;
    }
    return true;
  }

  void _scrollToFirstError(GlobalKey<FormState> formKey) {
    // Simple implementation - just scroll to the first focus node
    for (final focusNode in _focusNodes.values) {
      if (focusNode.context != null) {
        focusNode.requestFocus();
        _scrollToFocusNode(focusNode);
        break;
      }
    }
  }

  void _scrollToFocusNode(FocusNode focusNode) {
    final context = focusNode.context;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  @override
  void dispose() {
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }
}
