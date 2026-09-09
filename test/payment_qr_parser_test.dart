import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/services/payment_qr_parser.dart';

/// A GCash-style QR Ph P2M payload with a real CRC-16 checksum:
/// static merchant QR, ph.ppmi.p2m account (639952411234 / GcashXchange),
/// PHP currency, PH country, merchant name `Mi**** L T.`, city Manila,
/// additional data mobile + bill reference BILL-001.
const _qrPhPayload =
    '00020101021126470011ph.ppmi.p2m01126399524112340212GcashXchange'
    '5204541153036085802PH5911Mi**** L T.6006Manila'
    '622802126399524112340508BILL-00163046186';

/// A dynamic EMVCo payload carrying a fixed 10.00 PHP amount.
const _dynamicAmountPayload =
    '0002010102125303608540510.005802PH5910Store Name6304B703';

void main() {
  group('PaymentQrParser', () {
    test('recognizes a QR Ph merchant payload and extracts its fields', () {
      final decoded = PaymentQrParser.parse(_qrPhPayload);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.isRecognized, isTrue);
      expect(decoded.detectionSource, PaymentQrDetectionSource.qrPayload);
      expect(decoded.rawPayload, _qrPhPayload);
      expect(decoded.paymentNetwork, 'QR Ph');
      expect(decoded.merchantName, 'Mi**** L T.');
      expect(decoded.merchantCity, 'Manila');
      expect(decoded.countryCode, 'PH');
      expect(decoded.currencyCode, 'PHP');
      expect(decoded.accountIdentifier, '639952411234');
      expect(decoded.mobileNumber, '+63 995 241 1234');
      expect(decoded.qrReference, 'BILL-001');
      expect(decoded.isStatic, isTrue);
      expect(decoded.crcValid, isTrue);
    });

    test('parses a dynamic QR with a fixed amount', () {
      final decoded = PaymentQrParser.parse(_dynamicAmountPayload);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.isStatic, isFalse);
      expect(decoded.amount, 10.00);
      expect(decoded.currencyCode, 'PHP');
      expect(decoded.merchantName, 'Store Name');
      expect(decoded.crcValid, isTrue);
    });

    test('reports a failed CRC without discarding the parsed fields', () {
      // Same payload but a corrupted CRC value.
      final tampered =
          '${_qrPhPayload.substring(0, _qrPhPayload.length - 4)}0000';
      final decoded = PaymentQrParser.parse(tampered);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.crcValid, isFalse);
      expect(decoded.merchantName, 'Mi**** L T.');
    });

    test('marks plain text as decoded but not a payment QR', () {
      final decoded = PaymentQrParser.parse('hello world');

      expect(decoded.status, PaymentQrDecodeStatus.decodedUnparsed);
      expect(decoded.isRecognized, isFalse);
      expect(decoded.merchantName, isNull);
      expect(decoded.mobileNumber, isNull);
    });

    test('marks a URL payload as decoded but not a payment QR', () {
      final decoded = PaymentQrParser.parse('https://example.com/pay');

      expect(decoded.status, PaymentQrDecodeStatus.decodedUnparsed);
    });

    test('marks a truncated TLV payload as unparsed', () {
      final decoded = PaymentQrParser.parse('0002010102112650');

      expect(decoded.status, PaymentQrDecodeStatus.decodedUnparsed);
    });

    test('returns notDetected for an empty payload', () {
      expect(PaymentQrParser.parse('').status,
          PaymentQrDecodeStatus.notDetected);
      expect(PaymentQrParser.parse(null).status,
          PaymentQrDecodeStatus.notDetected);
    });

    test('does not fabricate a mobile number when none is encoded', () {
      // Merchant name and country only — no mobile anywhere, no CRC field.
      const payload = '0002010102115802PH5910Store Name';
      final decoded = PaymentQrParser.parse(payload);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.merchantName, 'Store Name');
      expect(decoded.mobileNumber, isNull);
      expect(decoded.accountIdentifier, isNull);
      expect(decoded.crcValid, isNull);
    });

    test('normalizes a masked PH mobile from a merchant account field', () {
      // Merchant account template 26: sub-tag 00 = GUI, sub-tag 01 holds a
      // masked mobile `955241****` (length 10).
      const mai = '0011ph.ppmi.p2m0110955241****';
      const payload =
          '0002010102112629${mai}5802PH5911Mi**** L T.';
      final decoded = PaymentQrParser.parse(payload);

      expect(decoded.status, PaymentQrDecodeStatus.recognized);
      expect(decoded.mobileNumber, '+63 955 241 ****');
      expect(decoded.accountIdentifier, '955241****');
    });

    test('accepts a mobile number from the additional data field', () {
      // Tag 62, sub-tag 02 is the EMVCo mobile number field.
      const addl = '0212639952411234';
      const payload = '0002010102115802PH6216$addl';
      final decoded = PaymentQrParser.parse(payload);

      expect(decoded.mobileNumber, '+63 995 241 1234');
    });
  });
}
