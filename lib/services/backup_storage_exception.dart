/// Exception thrown when a backup storage operation fails.
class BackupStorageException implements Exception {
  final String message;

  BackupStorageException(this.message);

  @override
  String toString() => 'BackupStorageException: $message';
}
