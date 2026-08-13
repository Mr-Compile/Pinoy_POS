/// Exception thrown when a user attempts an action they are not authorized to perform.
class AuthorizationException implements Exception {
  final String permission;
  final String message;

  AuthorizationException(this.permission, [String? message])
      : message = message ??
            'You do not have permission to perform this action ($permission).';

  @override
  String toString() => 'AuthorizationException: $message';
}
