import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/license_code_utils.dart';

void main() {
  group('LicenseCodeInputFormatter.format', () {
    test('inserts the dash after the fourth character', () {
      expect(LicenseCodeInputFormatter.format('NRV27YME'), 'NRV2-7YME');
    });

    test('formats partial input without a dangling dash', () {
      expect(LicenseCodeInputFormatter.format('N'), 'N');
      expect(LicenseCodeInputFormatter.format('NRV2'), 'NRV2');
      expect(LicenseCodeInputFormatter.format('NRV27'), 'NRV2-7');
    });

    test('uppercases and re-dashes lowercase input', () {
      expect(LicenseCodeInputFormatter.format('nrv27yme'), 'NRV2-7YME');
      expect(LicenseCodeInputFormatter.format('nrv2-7yme'), 'NRV2-7YME');
    });

    test('strips spaces, extra dashes, and punctuation', () {
      expect(LicenseCodeInputFormatter.format('nrv 27y me'), 'NRV2-7YME');
      expect(LicenseCodeInputFormatter.format('--NRV2--7YME'), 'NRV2-7YME');
      expect(LicenseCodeInputFormatter.format('NRV2 7YME!'), 'NRV2-7YME');
    });

    test('caps at 8 alphanumeric characters', () {
      expect(LicenseCodeInputFormatter.format('NRV27YME9999'), 'NRV2-7YME');
    });
  });

  group('LicenseCodeInputFormatter.formatEditUpdate', () {
    test('returns formatted text with the cursor at the end', () {
      final formatter = LicenseCodeInputFormatter();
      const value = TextEditingValue(text: 'nrv27yme');
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value);
      expect(result.text, 'NRV2-7YME');
      expect(result.selection.baseOffset, result.text.length);
    });
  });
}
