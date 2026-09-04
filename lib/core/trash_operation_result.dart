/// Result of a TrashService operation.
class TrashOperationResult {
  final bool success;
  final String message;

  const TrashOperationResult({
    required this.success,
    this.message = '',
  });

  static const successResult = TrashOperationResult(success: true);
  static const cancelled = TrashOperationResult(
    success: false,
    message: 'Cancelled',
  );

  TrashOperationResult withMessage(String message) {
    return TrashOperationResult(success: success, message: message);
  }
}
