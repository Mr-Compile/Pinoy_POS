import 'package:flutter/material.dart';

class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final bool enabled;
  final Widget? icon;
  final void Function(T?)? onChanged;
  final String? Function(T?)? validator;

  const AppDropdown({
    super.key,
    this.value,
    required this.items,
    this.labelText,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.icon,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      icon: icon,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        border: const OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}
