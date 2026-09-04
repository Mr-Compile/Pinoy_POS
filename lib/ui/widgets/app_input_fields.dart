import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared input-field components for the whole application.
///
/// These widgets provide a single place to define the app's modern input
/// language: filled surface, 16px radius, subtle border, clear focus state.
/// Visual styling (borders, fill, padding, icon colors, label/hint/error
/// styles) comes from the global [InputDecorationTheme] in `app_theme.dart`;
/// these wrappers only enforce consistent *usage* (labels, icons, keyboard
/// behavior) so CRUD forms never re-implement decoration.
///
/// Use:
///   - [AppTextFormField] for general text/number input in forms.
///   - [AppPasswordField] for any password/PIN-style secret input; it owns
///     the visibility-toggle suffix icon.
///   - [AppDropdownField] for dropdowns so they visually match text fields.
///   - [AppSearchField] for compact search bars.
class AppTextFormField extends StatelessWidget {
  const AppTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.prefix,
    this.prefixText,
    this.suffixIcon,
    this.suffix,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.autofillHints,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
    this.isDense = false,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? prefix;
  final String? prefixText;
  final IconData? suffixIcon;
  final Widget? suffix;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final GestureTapCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final effectiveMaxLines = obscureText ? 1 : maxLines;
    final effectiveMinLines = obscureText ? 1 : minLines;

    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        isDense: isDense,
        prefixIcon: prefix ??
            (prefixIcon != null ? Icon(prefixIcon) : null),
        prefixText: prefixText,
        suffixIcon: suffix ??
            (suffixIcon != null ? Icon(suffixIcon) : null),
        suffixText: suffixText,
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: effectiveMaxLines,
      minLines: effectiveMinLines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      onTap: onTap,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autovalidateMode: autovalidateMode,
    );
  }
}

/// A password/secret field with a built-in visibility toggle.
///
/// Wraps [AppTextFormField] and owns the `_obscure` state, so callers do not
/// need to manage it themselves. Set [enabled]/[isLoading] to disable the
/// toggle while a request is in flight.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    super.key,
    this.controller,
    this.label = 'Password',
    this.hint,
    this.prefixIcon,
    this.prefix,
    this.keyboardType = TextInputType.visiblePassword,
    this.textInputAction,
    this.enabled = true,
    this.isLoading = false,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.autofillHints = const [AutofillHints.password],
    this.isDense = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool isLoading;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final bool isDense;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveEnabled = widget.enabled && !widget.isLoading;

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      enabled: effectiveEnabled,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        isDense: widget.isDense,
        prefixIcon: widget.prefix ??
            (widget.prefixIcon != null ? Icon(widget.prefixIcon) : null),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          color: cs.onSurfaceVariant,
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: effectiveEnabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
        ),
      ),
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
    );
  }
}

/// A dropdown that visually matches the shared input-field design.
///
/// Keeps the same filled surface, radius, border and icon treatment as
/// [AppTextFormField] by reusing the global [InputDecorationTheme].
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    this.label,
    this.hint,
    this.initialValue,
    this.items = const [],
    this.onChanged,
    this.validator,
    this.prefixIcon,
    this.prefix,
    this.enabled = true,
    this.autofocus = false,
    this.isDense = false,
  });

  final String? label;
  final String? hint;
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final IconData? prefixIcon;
  final Widget? prefix;
  final bool enabled;
  final bool autofocus;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: isDense,
        prefixIcon: prefix ??
            (prefixIcon != null ? Icon(prefixIcon) : null),
      ),
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
    );
  }
}

/// A compact search field that shares the app's input design language but
/// with denser padding and a leading search icon.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        constraints: const BoxConstraints(minHeight: 44),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: onClear != null &&
                (controller == null || controller!.text.isNotEmpty)
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClear,
                tooltip: 'Clear search',
              )
            : null,
      ),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
