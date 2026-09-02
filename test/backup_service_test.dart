import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/services/backup_service.dart';

void main() {
  group('BackupService construction', () {
    test('can be constructed', () {
      final service = BackupService();
      expect(service, isNotNull);
    });
  });
}
