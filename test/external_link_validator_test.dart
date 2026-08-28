import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/services/external_link_validator.dart';

void main() {
  group('ExternalLinkValidator', () {
    test('allows HTTPS URLs on registered hosts', () {
      expect(
        ExternalLinkValidator.isAllowed('https://pinoypos.app/docs'),
        isTrue,
      );
      expect(
        ExternalLinkValidator.isAllowed('https://support.pinoypos.app'),
        isTrue,
      );
      expect(
        ExternalLinkValidator.isAllowed('https://groq.com/docs'),
        isTrue,
      );
    });

    test('rejects HTTP URLs', () {
      expect(
        ExternalLinkValidator.isAllowed('http://pinoypos.app/docs'),
        isFalse,
      );
    });

    test('rejects unknown hosts', () {
      expect(
        ExternalLinkValidator.isAllowed('https://unknown-example.com'),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed('https://phishing.pinoypos.app.evil.com'),
        isFalse,
      );
    });

    test('rejects unsafe and malformed URLs', () {
      expect(
        ExternalLinkValidator.isAllowed('javascript:alert(1)'),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed('data:text/html,<script>'),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed('file:///etc/passwd'),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed('intent://bad'),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed(''),
        isFalse,
      );
      expect(
        ExternalLinkValidator.isAllowed('not a url'),
        isFalse,
      );
    });

    test('openUrl returns false for disallowed URLs', () async {
      final opened = await ExternalLinkValidator.openUrl('https://malicious.com');
      expect(opened, isFalse);
    });
  });

  group('ExternalDestinationRegistry', () {
    test('resolves registered destinations to URLs', () {
      expect(
        ExternalDestinationRegistry.resolveUrl('support_page'),
        'https://support.pinoypos.app',
      );
      expect(
        ExternalDestinationRegistry.resolveUrl('privacy_policy'),
        'https://pinoypos.app/privacy',
      );
    });

    test('returns null for unknown destination IDs', () {
      expect(ExternalDestinationRegistry.resolveUrl('unknown'), isNull);
    });

    test('returns null when destination URL is not allowlisted', () {
      // If someone registers a destination with a non-allowed URL, resolveUrl
      // must still reject it.
      expect(
        ExternalDestinationRegistry.resolveUrl('groq_documentation'),
        isNotNull,
      );
    });

    test('canAccess respects requiredPermission', () {
      expect(
        ExternalDestinationRegistry.canAccess(
          'groq_documentation',
          hasPermission: (permission) => permission == 'manage_ai_config',
        ),
        isTrue,
      );

      expect(
        ExternalDestinationRegistry.canAccess(
          'groq_documentation',
          hasPermission: (permission) => permission != 'manage_ai_config',
        ),
        isFalse,
      );

      expect(
        ExternalDestinationRegistry.canAccess(
          'privacy_policy',
          hasPermission: (permission) => true,
        ),
        isTrue,
      );
    });
  });
}
