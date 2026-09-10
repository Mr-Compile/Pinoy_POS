import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// Shared input-field components for the whole application.
///
/// These widgets match the CRUD dialog mockup:
/// - labels sit above the field,
/// - icons are positioned at the bottom-left (single-line) or top-left
///   (multi-line) of the input and never overlap the text,
/// - fields are filled with the card surface, have a 12px radius and a
///   subtle border, and use a compact 44dp height.
///
/// Use:
///   - [AppTextFormField] for general text/number input in forms.
///   - [AppPasswordField] for any password/PIN-style secret input; it owns
///     the visibility-toggle suffix icon.
///   - [AppDropdownField] for dropdowns so they visually match text fields.
///   - [AppSearchField] for compact search bars.
///   - [AppDropdown] for controlled dropdowns in toolbars and filters.
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
    this.isDense = true,
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

  bool get _isMultiline =>
      (maxLines != null && maxLines! > 1) ||
      (minLines != null && minLines! > 1) ||
      maxLines == null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = _fieldTextStyle(context, enabled);
    final iconColor = _fieldIconColor(context, enabled);
    final hasOverlayIcon = prefixIcon != null;
    final leftPadding = hasOverlayIcon ? 40.0 : 12.0;
    final minHeight = _isMultiline ? 80.0 : 44.0;

    Widget field = TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      focusNode: focusNode,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: null,
        hintText: hint,
        helperText: helperText,
        isDense: isDense,
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.fromLTRB(
          prefix != null && !hasOverlayIcon ? 12.0 : leftPadding,
          11.0,
          12.0,
          11.0,
        ),
        constraints: BoxConstraints(minHeight: minHeight),
        hintStyle: textStyle.copyWith(color: cs.onSurfaceVariant),
        prefix: prefix != null && !hasOverlayIcon ? prefix : null,
        prefixText: prefixText,
        suffixIcon: suffixIcon != null
            ? Icon(suffixIcon, size: 18, color: iconColor)
            : suffix,
        suffixText: suffixText,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          maxWidth: 40,
          minHeight: 40,
          maxHeight: 40,
        ),
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textAlignVertical:
          _isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
      style: textStyle,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      minLines: _minLines,
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

    if (hasOverlayIcon) {
      field = Stack(
        clipBehavior: Clip.none,
        children: [
          field,
          _FieldIcon(
            icon: prefixIcon,
            isMultiline: _isMultiline,
            color: iconColor,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          _FieldLabel(label: label!),
          const SizedBox(height: 6.0),
        ],
        field,
      ],
    );
  }

  int? get _minLines {
    if (minLines != null) return minLines;
    if (maxLines != null && maxLines! > 1) return maxLines;
    if (maxLines == null) return 3;
    return null;
  }
}

/// A password/secret field with a built-in visibility toggle.
///
/// Wraps [TextFormField] and owns the `_obscure` state, so callers do not
/// need to manage it themselves. Set [enabled]/[isLoading] to disable the
/// toggle while a request is in flight.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    super.key,
    this.controller,
    this.label,
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
    this.isDense = true,
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
    final textStyle = _fieldTextStyle(context, effectiveEnabled);
    final iconColor = _fieldIconColor(context, effectiveEnabled);
    final hasOverlayIcon = widget.prefixIcon != null;
    final leftPadding = hasOverlayIcon ? 40.0 : 12.0;

    Widget field = TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      enabled: effectiveEnabled,
      decoration: InputDecoration(
        labelText: null,
        hintText: widget.hint,
        isDense: widget.isDense,
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.fromLTRB(
          widget.prefix != null && !hasOverlayIcon ? 12.0 : leftPadding,
          11.0,
          12.0,
          11.0,
        ),
        constraints: const BoxConstraints(minHeight: 44.0),
        hintStyle: textStyle.copyWith(color: cs.onSurfaceVariant),
        prefix: widget.prefix != null && !hasOverlayIcon ? widget.prefix : null,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: iconColor,
          ),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: effectiveEnabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          maxWidth: 40,
          minHeight: 40,
          maxHeight: 40,
        ),
      ),
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textAlignVertical: TextAlignVertical.center,
      style: textStyle,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
    );

    if (hasOverlayIcon) {
      field = Stack(
        clipBehavior: Clip.none,
        children: [
          field,
          _FieldIcon(
            icon: widget.prefixIcon,
            isMultiline: false,
            color: iconColor,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          _FieldLabel(label: widget.label!),
          const SizedBox(height: 6.0),
        ],
        field,
      ],
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
    this.isDense = true,
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
    final cs = Theme.of(context).colorScheme;
    final textStyle = _fieldTextStyle(context, enabled);
    final iconColor = _fieldIconColor(context, enabled);
    final hasOverlayIcon = prefixIcon != null;
    final leftPadding = hasOverlayIcon ? 40.0 : 12.0;

    Widget field = DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      autofocus: autofocus,
      isExpanded: true,
      borderRadius: BorderRadius.circular(AppRadius.input),
      icon: Icon(
        Icons.arrow_drop_down,
        size: 24,
        color: cs.onSurfaceVariant,
      ),
      style: textStyle,
      decoration: InputDecoration(
        labelText: null,
        hintText: hint,
        isDense: isDense,
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.fromLTRB(
          prefix != null && !hasOverlayIcon ? 12.0 : leftPadding,
          11.0,
          12.0,
          11.0,
        ),
        constraints: const BoxConstraints(minHeight: 44.0),
        hintStyle: textStyle.copyWith(color: cs.onSurfaceVariant),
        prefix: prefix != null && !hasOverlayIcon ? prefix : null,
      ),
    );

    if (hasOverlayIcon) {
      field = Stack(
        clipBehavior: Clip.none,
        children: [
          field,
          _FieldIcon(
            icon: prefixIcon,
            isMultiline: false,
            color: iconColor,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          _FieldLabel(label: label!),
          const SizedBox(height: 6.0),
        ],
        field,
      ],
    );
  }
}

/// A controlled dropdown that matches the shared input-field design.
///
/// The selected [value] is managed by the parent, so the dropdown updates
/// whenever the parent rebuilds with a new value. Use this in filter bars,
/// toolbars, and other places where the selection is screen state.
///
/// For form fields that only need an initial value, use [AppDropdownField].
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    this.label,
    this.hint,
    required this.value,
    required this.items,
    this.onChanged,
    this.prefixIcon,
    this.prefix,
    this.enabled = true,
    this.isDense = true,
  });

  final String? label;
  final String? hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final IconData? prefixIcon;
  final Widget? prefix;
  final bool enabled;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = _fieldTextStyle(context, enabled);
    final iconColor = _fieldIconColor(context, enabled);
    final hasOverlayIcon = prefixIcon != null;
    final leftPadding = hasOverlayIcon ? 40.0 : 12.0;

    final child = DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        hint: hint != null ? Text(hint!) : null,
        isDense: isDense,
        isExpanded: true,
        icon: Icon(
          Icons.arrow_drop_down,
          size: 24,
          color: cs.onSurfaceVariant,
        ),
        style: textStyle,
        items: items,
        onChanged: enabled ? onChanged : null,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
    );

    Widget field = InputDecorator(
      isEmpty: value == null,
      decoration: InputDecoration(
        labelText: null,
        hintText: hint,
        isDense: isDense,
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.fromLTRB(
          prefix != null && !hasOverlayIcon ? 12.0 : leftPadding,
          11.0,
          12.0,
          11.0,
        ),
        constraints: const BoxConstraints(minHeight: 44.0),
        hintStyle: textStyle.copyWith(color: cs.onSurfaceVariant),
        prefix: prefix != null && !hasOverlayIcon ? prefix : null,
      ),
      child: child,
    );

    if (hasOverlayIcon) {
      field = Stack(
        clipBehavior: Clip.none,
        children: [
          field,
          _FieldIcon(
            icon: prefixIcon,
            isMultiline: false,
            color: iconColor,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          _FieldLabel(label: label!),
          const SizedBox(height: 6.0),
        ],
        field,
      ],
    );
  }
}

/// A compact search field that shares the app's input design language.
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
    final cs = Theme.of(context).colorScheme;
    final textStyle = _fieldTextStyle(context, enabled);
    final iconColor = _fieldIconColor(context, enabled);

    Widget field({required bool showClear}) => TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: cs.surface,
            contentPadding: const EdgeInsets.fromLTRB(40.0, 11.0, 12.0, 11.0),
            constraints: const BoxConstraints(minHeight: 44.0),
            hintStyle: textStyle.copyWith(color: cs.onSurfaceVariant),
            suffixIcon: showClear && onClear != null
                ? IconButton(
                    icon: Icon(Icons.close, size: 20, color: iconColor),
                    onPressed: onClear,
                    tooltip: 'Clear search',
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              maxWidth: 40,
              minHeight: 40,
              maxHeight: 40,
            ),
          ),
          textAlignVertical: TextAlignVertical.center,
          style: textStyle,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        );

    final fieldWithIcon = Stack(
      clipBehavior: Clip.none,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller ?? _emptyController,
          builder: (context, value, _) {
            final showClear = onClear != null &&
                (controller == null || value.text.isNotEmpty);
            return field(showClear: showClear);
          },
        ),
        _FieldIcon(
          icon: Icons.search,
          isMultiline: false,
          color: iconColor,
        ),
      ],
    );

    return fieldWithIcon;
  }
}

final _emptyController = ValueNotifier<TextEditingValue>(
  const TextEditingValue(),
);

/// A small left-aligned icon used inside text, dropdown and search fields.
///
/// Matches the mockup `.field-icon`: 18px, muted, pointer-events none,
/// positioned at the bottom-left for single-line inputs and the top-left
/// for multi-line textareas.
class _FieldIcon extends StatelessWidget {
  final IconData? icon;
  final bool isMultiline;
  final Color color;

  const _FieldIcon({
    this.icon,
    required this.isMultiline,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();

    final child = IgnorePointer(
      child: Icon(icon, size: 18, color: color),
    );

    if (isMultiline) {
      return Positioned(left: 12.0, top: 12.0, child: child);
    }

    return Positioned(left: 12.0, top: 14.0, child: child);
  }
}

/// A field label matching the CRUD mockup.
class _FieldLabel extends StatelessWidget {
  final String label;

  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
    );
  }
}

TextStyle _fieldTextStyle(BuildContext context, bool enabled) {
  final cs = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.bodyMedium ??
      const TextStyle(fontSize: 13, fontFamily: 'Inter');
  final color = enabled
      ? cs.onSurface
      : cs.onSurface.withValues(alpha: 0.38);
  return base.copyWith(fontSize: 13, color: color);
}

Color _fieldIconColor(BuildContext context, bool enabled) {
  final cs = Theme.of(context).colorScheme;
  return enabled
      ? cs.onSurfaceVariant
      : cs.onSurface.withValues(alpha: 0.38);
}
