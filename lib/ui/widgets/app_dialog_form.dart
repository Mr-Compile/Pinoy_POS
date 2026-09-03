import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

/// Builder for the body of an [AppDialogForm].
typedef AppDialogFormChildBuilder<T> = Widget Function(
  BuildContext context,
  AppDialogFormState<T> state,
);

/// Builder for the actions of an [AppDialogForm].
typedef AppDialogFormActionsBuilder<T> = List<AppDialogAction> Function(
  BuildContext context,
  AppDialogFormState<T> state,
);

/// Callback for [PopScope] invocations.
///
/// [context] is the [AppDialogForm] build context, still valid while the
/// dialog is being mounted and the pop is being considered.
typedef AppDialogFormPopCallback<T> = void Function(
  BuildContext context,
  AppDialogFormState<T> state,
  bool didPop,
  Object? result,
);

/// A reusable, lifecycle-safe form host for Pinoy POS dialogs.
///
/// [AppDialogForm] is a [StatefulWidget] that owns all form state:
/// - a [GlobalKey<FormState>]
/// - `isSaving` / `hasChanges` flags
/// - any [TextEditingController]s created by [textController]
/// - any arbitrary dialog values created by [value]/[setValue]
///
/// All [TextEditingController]s are disposed when the dialog route is
/// disposed, so parent screens must never dispose them. Dialogs built with
/// [AppDialogForm] should return a result via [pop] and let the caller perform
/// side effects (refresh, snackbars, further dialogs) **after** the
/// [showDialog] future resolves.
///
/// This prevents the two root-cause families that produced the
/// "Tried to build dirty widgets in the wrong build scope" exceptions:
/// 1. Text controllers disposed by the parent before the route is unmounted.
/// 2. `setState` / provider refresh called from dialog action callbacks
///    while the route is being popped.
class AppDialogForm<T> extends StatefulWidget {
  const AppDialogForm({
    super.key,
    required this.type,
    required this.title,
    this.message,
    this.canPop = true,
    this.onPopInvokedWithResult,
    required this.childBuilder,
    required this.actionsBuilder,
  });

  final AppDialogType type;
  final String title;
  final String? message;

  /// Whether the system back gesture may pop this dialog without
  /// consultation. When [canPop] is `false`, [onPopInvokedWithResult] is
  /// called with `didPop == false` and the host is responsible for deciding
  /// whether to call [AppDialogFormState.pop].
  final bool canPop;

  /// Optional handler for [PopScope.onPopInvokedWithResult].
  final AppDialogFormPopCallback<T>? onPopInvokedWithResult;

  /// Builds the form body. Use [AppDialogFormState.textController] and
  /// [AppDialogFormState.value] / [AppDialogFormState.setValue] here.
  final AppDialogFormChildBuilder<T> childBuilder;

  /// Builds the dialog actions. Cancel should call
  /// [AppDialogFormState.pop] with a cancelled/empty result; Save should
  /// perform the operation and then call [AppDialogFormState.pop] with the
  /// result, or [AppDialogFormState.setSaving(false)] on error.
  final AppDialogFormActionsBuilder<T> actionsBuilder;

  @override
  AppDialogFormState<T> createState() => AppDialogFormState<T>();
}

class AppDialogFormState<T> extends State<AppDialogForm<T>> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final _controllers = <String, TextEditingController>{};
  final _values = <String, Object?>{};

  bool isSaving = false;
  bool hasChanges = false;

  /// Returns a [TextEditingController] for [key], creating it on the first
  /// build and caching it for the lifetime of the dialog.
  ///
  /// The [text] argument is only used when the controller is first created.
  /// Subsequent rebuilds will keep the existing text.
  TextEditingController textController(String key, {String? text}) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: text),
    );
  }

  /// Returns the stored value for [key], initialising it to [initial]
  /// if it has not been set.
  ///
  /// The type parameter is the *non-null* value type; the method returns
  /// the nullable equivalent.
  TVal? value<TVal>(String key, [TVal? initial]) {
    _values.putIfAbsent(key, () => initial);
    return _values[key] as TVal?;
  }

  /// Stores [value] under [key] and marks the form as changed.
  void setValue<TVal>(String key, TVal? value) {
    setState(() {
      _values[key] = value;
      hasChanges = true;
    });
  }

  /// Marks the form as changed.
  void markChanged() {
    if (hasChanges) return;
    setState(() => hasChanges = true);
  }

  /// Updates the loading state. Only call this while the dialog is still
  /// mounted and before [pop] is called; never call it after [pop].
  void setSaving(bool value) {
    setState(() => isSaving = value);
  }

  /// Pops the dialog with [result], but only while the dialog is still
  /// mounted.
  ///
  /// Callers should **not** call [setSaving] or any other [setState]-based
  /// helper after [pop] -- the widget will be disposed by the framework.
  void pop(T result) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget dialog = AppDialog(
      type: widget.type,
      title: widget.title,
      message: widget.message,
      dismissible: widget.canPop,
      actions: widget.actionsBuilder(context, this),
      child: widget.childBuilder(context, this),
    );

    if (!widget.canPop || widget.onPopInvokedWithResult != null) {
      dialog = PopScope(
        canPop: widget.canPop,
        onPopInvokedWithResult: (didPop, result) {
          widget.onPopInvokedWithResult?.call(context, this, didPop, result);
        },
        child: dialog,
      );
    }

    return dialog;
  }
}
