import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/data/models/settings.dart';

/// Regression tests for [Settings.fromMap] resilience.
///
/// The settings load path backs Payment Settings, the POS payment dialog,
/// and the GCash flow — a malformed row must not take them all down.
void main() {
  Map<String, dynamic> baseRow() => {
        'id': 1,
        'store_name': 'Test Store',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      };

  group('Settings.fromMap', () {
    test('parses a normal row', () {
      final settings = Settings.fromMap(baseRow());
      expect(settings.storeName, 'Test Store');
      expect(settings.createdAt, DateTime(2026, 1, 1));
    });

    test('missing created_at/updated_at fall back to epoch instead of throwing', () {
      final row = baseRow()
        ..remove('created_at')
        ..remove('updated_at');

      final settings = Settings.fromMap(row);

      expect(settings.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(settings.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('null timestamps fall back to epoch instead of throwing', () {
      final row = baseRow()
        ..['created_at'] = null
        ..['updated_at'] = null;

      final settings = Settings.fromMap(row);

      expect(settings.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(settings.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('malformed timestamp strings fall back to epoch instead of throwing', () {
      final row = baseRow()
        ..['created_at'] = 'not-a-date'
        ..['updated_at'] = '##invalid##';

      final settings = Settings.fromMap(row);

      expect(settings.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(settings.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
