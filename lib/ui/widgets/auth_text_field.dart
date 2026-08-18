import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;
  final bool autofocus;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.focusNode,
    this.suffixIcon,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.keyboardType = TextInputType.text,
    this.onFieldSubmitted,
    this.validator,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
      obscureText: obscureText,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      autofocus: autofocus,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
    );
  }
}
