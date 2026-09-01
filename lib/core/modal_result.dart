enum _ModalResultType {
  saved,
  confirmed,
  cancelled,
  dismissed,
  failed,
}

/// Shared, non-nullable result for every dialog and modal in Pinoy POS.
///
/// Callers no longer have to guess whether `null`, `false`, or an empty
/// string means the user cancelled or the operation failed. Every modal
/// returns a `ModalResult` that is exactly one of:
///
/// - [ModalResult.saved] — the user submitted/saved data.
/// - [ModalResult.confirmed] — the user confirmed an action.
/// - [ModalResult.cancelled] — the user pressed Cancel or the device back
///   button.
/// - [ModalResult.dismissed] — the user tapped outside the dialog or used a
///   close/X affordance to dismiss it without taking an action.
/// - [ModalResult.failed] — the operation was actually attempted and failed.
///
/// `cancelled` and `dismissed` are grouped under [isCancelled] because they
/// share the same caller semantics: the user chose not to proceed and no
/// database side effect must occur. The distinction is still available via
/// [isDismissed] if a screen wants to treat a tap-outside differently.
class ModalResult<T> {
  final _ModalResultType _type;

  /// Optional typed payload carried on [ModalResult.saved].
  final T? value;

  /// Human-readable failure message on [ModalResult.failed].
  final String? error;

  /// Optional underlying exception/cause on [ModalResult.failed] for logging.
  final Object? cause;

  const ModalResult._(
    this._type, {
    this.value,
    this.error,
    this.cause,
  });

  const ModalResult.saved([T? value])
      : this._(_ModalResultType.saved, value: value);

  const ModalResult.confirmed()
      : this._(_ModalResultType.confirmed);

  const ModalResult.cancelled()
      : this._(_ModalResultType.cancelled);

  const ModalResult.dismissed()
      : this._(_ModalResultType.dismissed);

  const ModalResult.failed({String? error, Object? cause})
      : this._(_ModalResultType.failed, error: error, cause: cause);

  bool get isSaved => _type == _ModalResultType.saved;

  bool get isConfirmed => _type == _ModalResultType.confirmed;

  bool get isCancelled =>
      _type == _ModalResultType.cancelled ||
      _type == _ModalResultType.dismissed;

  bool get isDismissed => _type == _ModalResultType.dismissed;

  bool get isFailed => _type == _ModalResultType.failed;

  bool get isSuccess => isSaved || isConfirmed;

  bool get isCompleted => isSuccess || isFailed;

  /// Pattern match over every possible result type.
  R when<R>({
    required R Function(T? value) saved,
    required R Function() confirmed,
    required R Function() cancelled,
    required R Function() dismissed,
    required R Function(String? error, Object? cause) failed,
  }) {
    return switch (_type) {
      _ModalResultType.saved => saved(value),
      _ModalResultType.confirmed => confirmed(),
      _ModalResultType.cancelled => cancelled(),
      _ModalResultType.dismissed => dismissed(),
      _ModalResultType.failed => failed(error, cause),
    };
  }

  /// Convenience for result-or-default.
  R whenOrDefault<R>({
    R Function(T? value)? saved,
    R Function()? confirmed,
    R Function()? cancelled,
    R Function()? dismissed,
    R Function(String? error, Object? cause)? failed,
    required R Function() orDefault,
  }) {
    return switch (_type) {
      _ModalResultType.saved => saved?.call(value) ?? orDefault(),
      _ModalResultType.confirmed => confirmed?.call() ?? orDefault(),
      _ModalResultType.cancelled => cancelled?.call() ?? orDefault(),
      _ModalResultType.dismissed => dismissed?.call() ?? orDefault(),
      _ModalResultType.failed => failed?.call(error, cause) ?? orDefault(),
    };
  }

  @override
  String toString() =>
      'ModalResult.${_type.name}(value: $value, error: $error)';
}
