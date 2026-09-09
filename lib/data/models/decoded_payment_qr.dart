/// How a piece of payment QR information was obtained.
///
/// Only [qrPayload] is authoritative — the value came from the decoded QR
/// payload itself. The enum exists so future helpers (e.g. OCR of text
/// printed next to the QR) can be marked as unverified instead of being
/// silently treated as payment identity data.
enum PaymentQrDetectionSource {
  /// No data was detected.
  none,

  /// The value was decoded directly from the QR payload.
  qrPayload,
}

/// Outcome of decoding and interpreting the merchant's payment QR image.
enum PaymentQrDecodeStatus {
  /// No image was supplied or no QR could be found in the image.
  notDetected,

  /// The image file could not be read or decoded at all.
  unreadable,

  /// A QR code was decoded but the payload is not a recognized payment QR.
  decodedUnparsed,

  /// A QR code was decoded and recognized as an EMVCo-compatible payment QR.
  recognized,
}

/// Structured result of decoding the merchant payment QR.
///
/// Produced by `PaymentQrService.decodePaymentQr` (image → payload) and
/// `PaymentQrParser.parse` (payload → fields). Every field is populated only
/// when the decoded payload actually contains it — nothing is fabricated.
/// Missing fields stay `null` so the UI can hide them instead of rendering
/// placeholder dashes.
class DecodedPaymentQr {
  /// The raw QR payload as decoded. Exposed for diagnostics; the UI must not
  /// show this raw string to the cashier.
  final String? rawPayload;

  /// Whether a QR was found and how far interpretation progressed.
  final PaymentQrDecodeStatus status;

  /// Where [merchantName]/[mobileNumber]/[accountIdentifier] came from.
  final PaymentQrDetectionSource detectionSource;

  /// Human-readable payment network, e.g. `QR Ph`, `GCash`, `InstaPay`,
  /// or the raw globally-unique identifier when it cannot be mapped.
  final String? paymentNetwork;

  /// Merchant name from EMVCo tag 59, when present.
  final String? merchantName;

  /// Merchant city from EMVCo tag 60, when present.
  final String? merchantCity;

  /// ISO 3166-1 alpha-2 country code from EMVCo tag 58, when present.
  final String? countryCode;

  /// Currency code resolved from EMVCo tag 53 (ISO 4217 numeric), e.g. `PHP`.
  final String? currencyCode;

  /// Fixed transaction amount from EMVCo tag 54, when the QR encodes one.
  final double? amount;

  /// Merchant account / payment identifier from the merchant account
  /// information template (EMVCo tags 02–51, sub-tag 01), when present.
  final String? accountIdentifier;

  /// A Philippine mobile number extracted from the payload, when one is
  /// actually encoded (EMVCo additional-data mobile field or a merchant
  /// account value that matches a PH mobile shape, including masked values
  /// such as `955 241 ****`). Null when the payload does not encode one.
  final String? mobileNumber;

  /// Reference/bill information carried by the QR (EMVCo tag 62 sub-fields),
  /// when present. This is the *QR's own* reference and must not be confused
  /// with the post-payment GCash transaction reference the cashier enters.
  final String? qrReference;

  /// True when the QR is a reusable static merchant QR (EMVCo tag 01 = `11`)
  /// rather than a one-time dynamic QR (tag 01 = `12`). Null when unknown.
  final bool? isStatic;

  /// CRC-16 validation result for the payload when a CRC is present.
  /// Null when the payload carries no CRC field.
  final bool? crcValid;

  const DecodedPaymentQr({
    this.rawPayload,
    required this.status,
    this.detectionSource = PaymentQrDetectionSource.none,
    this.paymentNetwork,
    this.merchantName,
    this.merchantCity,
    this.countryCode,
    this.currencyCode,
    this.amount,
    this.accountIdentifier,
    this.mobileNumber,
    this.qrReference,
    this.isStatic,
    this.crcValid,
  });

  /// Empty result used when there is no image or no QR was found.
  const DecodedPaymentQr.notDetected()
      : rawPayload = null,
        status = PaymentQrDecodeStatus.notDetected,
        detectionSource = PaymentQrDetectionSource.none,
        paymentNetwork = null,
        merchantName = null,
        merchantCity = null,
        countryCode = null,
        currencyCode = null,
        amount = null,
        accountIdentifier = null,
        mobileNumber = null,
        qrReference = null,
        isStatic = null,
        crcValid = null;

  /// Whether the payload was recognized as a payment QR.
  bool get isRecognized => status == PaymentQrDecodeStatus.recognized;

  /// Whether any merchant/payee identity field was decoded.
  bool get hasMerchantInfo =>
      merchantName != null || mobileNumber != null || accountIdentifier != null;

  /// Whether the payload carries any displayable payment metadata at all.
  bool get hasAnyDetails =>
      hasMerchantInfo ||
      paymentNetwork != null ||
      amount != null ||
      currencyCode != null;
}
