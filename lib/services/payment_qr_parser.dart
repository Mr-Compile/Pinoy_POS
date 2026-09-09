import 'dart:convert';

import '../data/models/decoded_payment_qr.dart';

/// Parses EMVCo Merchant Presented Mode (MPM) QR payloads — the standard
/// used by QR Ph, GCash, and other InstaPay-joined payment codes in the
/// Philippines.
///
/// The payload is a flat TLV list: two digits for the tag, two digits for
/// the value length, then the value. Tags 02–51 (merchant account
/// information) and tag 62 (additional data) contain nested TLV lists of
/// their own.
///
/// The parser is deliberately conservative: it only reports fields that are
/// actually present and structurally valid. It never invents merchant data
/// and never converts unrelated fields into identity data.
class PaymentQrParser {
  PaymentQrParser._();

  /// Tag of the additional data field template.
  static const int _additionalDataTag = 62;

  /// Tag of the CRC field.
  static const int _crcTag = 63;

  /// Interprets [raw] as an EMVCo payment QR payload.
  ///
  /// Returns a [DecodedPaymentQr] with [PaymentQrDecodeStatus.recognized]
  /// when the payload parses as EMVCo and carries at least one meaningful
  /// payment field, or [PaymentQrDecodeStatus.decodedUnparsed] when the
  /// payload is not a payment QR (plain text, URL, malformed TLV, …).
  static DecodedPaymentQr parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const DecodedPaymentQr.notDetected();
    }

    final fields = _parseTlv(raw);
    if (fields == null) {
      return DecodedPaymentQr(
        rawPayload: raw,
        status: PaymentQrDecodeStatus.decodedUnparsed,
      );
    }

    final payloadFormat = fields[0];
    final pointOfInitiation = fields[1];
    final merchantAccounts = _merchantAccounts(fields);
    final additionalData = _parseTlv(fields[_additionalDataTag] ?? '');

    final merchantName = _clean(fields[59]);
    final merchantCity = _clean(fields[60]);
    final countryCode = _clean(fields[58]);
    final currencyCode = _currencyName(fields[53]);
    final amount = _parseAmount(fields[54]);
    final gui = _clean(merchantAccounts.isNotEmpty
        ? merchantAccounts.first[0]
        : null);
    final accountIdentifier = _clean(merchantAccounts.isNotEmpty
        ? merchantAccounts.first[1]
        : null);
    final mobileNumber = _extractMobileNumber(merchantAccounts, additionalData);
    final qrReference = _extractQrReference(additionalData);

    final looksEmvco = payloadFormat == '01' ||
        payloadFormat == '02' ||
        merchantName != null ||
        merchantAccounts.isNotEmpty;

    if (!looksEmvco) {
      return DecodedPaymentQr(
        rawPayload: raw,
        status: PaymentQrDecodeStatus.decodedUnparsed,
      );
    }

    return DecodedPaymentQr(
      rawPayload: raw,
      status: PaymentQrDecodeStatus.recognized,
      detectionSource: PaymentQrDetectionSource.qrPayload,
      paymentNetwork: _networkName(gui),
      merchantName: merchantName,
      merchantCity: merchantCity,
      countryCode: countryCode,
      currencyCode: currencyCode,
      amount: amount,
      accountIdentifier: accountIdentifier,
      mobileNumber: mobileNumber,
      qrReference: qrReference,
      isStatic: pointOfInitiation == '11'
          ? true
          : pointOfInitiation == '12'
              ? false
              : null,
      crcValid: _crcValid(raw, fields[_crcTag]),
    );
  }

  /// Parses a TLV blob into a tag→value map, or returns null when the blob
  /// is structurally invalid (truncated value, non-numeric tag/length).
  ///
  /// Returns an empty map for an empty blob so nested templates can be
  /// parsed unconditionally.
  static Map<int, String>? _parseTlv(String data) {
    final result = <int, String>{};
    var index = 0;
    while (index < data.length) {
      if (index + 4 > data.length) return null;
      final tag = int.tryParse(data.substring(index, index + 2));
      final length = int.tryParse(data.substring(index + 2, index + 4));
      if (tag == null || length == null) return null;
      index += 4;
      if (index + length > data.length) return null;
      result[tag] = data.substring(index, index + length);
      index += length;
    }
    return result;
  }

  /// Parsed merchant account information templates (tags 02–51), each as a
  /// sub-tag→value map. Malformed nested templates are skipped rather than
  /// failing the whole parse.
  static List<Map<int, String>> _merchantAccounts(Map<int, String> fields) {
    final templates = <Map<int, String>>[];
    for (var tag = 2; tag <= 51; tag++) {
      final value = fields[tag];
      if (value == null || value.isEmpty) continue;
      final parsed = _parseTlv(value);
      if (parsed != null) templates.add(parsed);
    }
    return templates;
  }

  /// Maps an ISO 4217 numeric currency code to its alphabetic code.
  /// Only codes relevant to the payment ecosystem are mapped; unknown codes
  /// are returned verbatim so nothing is misreported.
  static String? _currencyName(String? numeric) {
    final cleaned = _clean(numeric);
    if (cleaned == null) return null;
    return switch (cleaned) {
      '608' => 'PHP',
      '840' => 'USD',
      _ => cleaned,
    };
  }

  static double? _parseAmount(String? raw) {
    final cleaned = _clean(raw);
    if (cleaned == null) return null;
    final amount = double.tryParse(cleaned);
    if (amount == null || amount < 0) return null;
    return amount;
  }

  /// Maps a globally-unique identifier (merchant account sub-tag 00) to a
  /// readable network name. Unknown identifiers are returned verbatim.
  static String? _networkName(String? gui) {
    final cleaned = _clean(gui);
    if (cleaned == null) return null;
    final lower = cleaned.toLowerCase();
    if (lower.contains('ppmi') || lower.contains('qrph')) return 'QR Ph';
    if (lower.contains('gcash')) return 'GCash';
    if (lower.contains('instapay')) return 'InstaPay';
    if (lower.contains('paymaya') || lower.contains('maya')) return 'Maya';
    return cleaned;
  }

  /// Extracts a Philippine mobile number when — and only when — the payload
  /// actually encodes one:
  ///
  /// 1. The EMVCo additional data mobile field (tag 62, sub-tag 02).
  /// 2. A merchant account sub-field value that matches a PH mobile shape.
  ///
  /// Masked values such as `955241****` are accepted because GCash merchant
  /// QRs legitimately encode masked account numbers. Values that do not look
  /// like a PH mobile are ignored rather than misreported.
  static String? _extractMobileNumber(
    List<Map<int, String>> merchantAccounts,
    Map<int, String>? additionalData,
  ) {
    final declared = _normalizePhMobile(additionalData?[2]);
    if (declared != null) return declared;

    for (final template in merchantAccounts) {
      for (final value in template.values) {
        final normalized = _normalizePhMobile(value);
        if (normalized != null) return normalized;
      }
    }
    return null;
  }

  /// Normalizes a value into `+63 9XX XXX XXXX` display form, preserving
  /// mask characters. Returns null when the value is not a PH mobile.
  static String? _normalizePhMobile(String? raw) {
    final cleaned = _clean(raw);
    if (cleaned == null) return null;
    final compact = cleaned.replaceAll(RegExp(r'[\s\-()]'), '');
    var local = compact.startsWith('+') ? compact.substring(1) : compact;
    if (local.startsWith('63')) {
      local = local.substring(2);
    } else if (local.startsWith('0')) {
      local = local.substring(1);
    }
    final isMobileShape = local.length == 10 &&
        local.startsWith('9') &&
        RegExp(r'^[0-9*]+$').hasMatch(local);
    if (!isMobileShape) return null;
    return '+63 ${local.substring(0, 3)} ${local.substring(3, 6)} '
        '${local.substring(6)}';
  }

  /// Reference data carried inside the QR itself (additional data bill
  /// number / reference label). This is distinct from the post-payment
  /// GCash transaction reference the cashier enters after payment.
  static String? _extractQrReference(Map<int, String>? additionalData) {
    if (additionalData == null) return null;
    return _clean(additionalData[5]) ?? _clean(additionalData[1]);
  }

  /// Verifies the CRC-16/CCITT-FALSE checksum when the payload carries one
  /// (tag 63). Returns null when no CRC field is present.
  static bool? _crcValid(String raw, String? crcField) {
    final cleaned = _clean(crcField);
    if (cleaned == null || cleaned.length != 4) return null;

    // The CRC covers everything up to and including the "6304" marker.
    final markerIndex = raw.lastIndexOf('6304');
    if (markerIndex < 0) return null;
    final body = raw.substring(0, markerIndex + 4);

    var crc = 0xFFFF;
    for (final unit in utf8.encode(body)) {
      crc ^= unit << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    final expected = crc.toRadixString(16).toUpperCase().padLeft(4, '0');
    return expected == cleaned.toUpperCase();
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
