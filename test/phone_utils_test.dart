import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/phone_utils.dart';

void main() {
  group('PhoneUtils.normalizePhMobile', () {
    test('strips spaces and punctuation', () {
      expect(PhoneUtils.normalizePhMobile('0926 585 2171'), '09265852171');
      expect(PhoneUtils.normalizePhMobile('0926-585-2171'), '09265852171');
    });

    test('converts +63 prefix to 0', () {
      expect(PhoneUtils.normalizePhMobile('+63 926 585 2171'), '09265852171');
      expect(PhoneUtils.normalizePhMobile('639265852171'), '09265852171');
    });

    test('leaves short 63-prefixed input untouched', () {
      expect(PhoneUtils.normalizePhMobile('6392'), '6392');
    });
  });

  group('PhoneUtils.formatPhMobile', () {
    test('groups digits as 4-3-4', () {
      expect(PhoneUtils.formatPhMobile('09265852171'), '0926 585 2171');
    });

    test('formats partial input', () {
      expect(PhoneUtils.formatPhMobile('0926'), '0926');
      expect(PhoneUtils.formatPhMobile('0926585'), '0926 585');
      expect(PhoneUtils.formatPhMobile('09265852'), '0926 585 2');
    });

    test('normalizes and formats +63 input', () {
      expect(PhoneUtils.formatPhMobile('+639265852171'), '0926 585 2171');
    });
  });

  group('PhoneUtils.isValidPhMobile', () {
    test('accepts an 11-digit 09 number', () {
      expect(PhoneUtils.isValidPhMobile('09265852171'), isTrue);
      expect(PhoneUtils.isValidPhMobile('0926 585 2171'), isTrue);
    });

    test('accepts +63 form', () {
      expect(PhoneUtils.isValidPhMobile('+63 926 585 2171'), isTrue);
    });

    test('rejects wrong length', () {
      expect(PhoneUtils.isValidPhMobile('0926585217'), isFalse);
      expect(PhoneUtils.isValidPhMobile('092658521712'), isFalse);
      expect(PhoneUtils.isValidPhMobile(''), isFalse);
    });

    test('rejects non-09 prefixes', () {
      expect(PhoneUtils.isValidPhMobile('08265852171'), isFalse);
      expect(PhoneUtils.isValidPhMobile('63265852171'), isFalse);
    });
  });

  group('PhMobileInputFormatter', () {
    TextEditingValue apply(String text) {
      return PhMobileInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: text),
      );
    }

    test('formats digits with spaces as typed', () {
      expect(apply('0926').text, '0926');
      expect(apply('09265').text, '0926 5');
      expect(apply('09265852171').text, '0926 585 2171');
    });

    test('caps input at 11 digits', () {
      expect(apply('09265852171999').text, '0926 585 2171');
    });

    test('strips non-digits while typing', () {
      expect(apply('09ab26').text, '0926');
    });
  });
}
