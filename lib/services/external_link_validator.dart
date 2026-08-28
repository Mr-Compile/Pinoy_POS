import 'package:url_launcher/url_launcher.dart';
import 'package:pinoy_pos/data/models/external_destination.dart';

/// A trusted allowlist for external URLs opened from AI assistant actions.
///
/// AI-generated URLs are never opened directly. The model requests a
/// registered [ExternalDestination] by [id], and the application resolves the
/// final URL, validates the scheme and host, and opens it only if it is on
/// the allowlist.
class ExternalLinkValidator {
  ExternalLinkValidator._();

  /// Allowed URL schemes. Only HTTPS by default; HTTP is rejected unless the
  /// application explicitly needs it.
  static const _allowedSchemes = {'https'};

  /// Allowed hosts. Add only hosts the POS application intentionally supports.
  static const _allowedHosts = {
    'pinoypos.app',
    'www.pinoypos.app',
    'groq.com',
    'www.groq.com',
    'help.pinoypos.app',
    'support.pinoypos.app',
  };

  /// Returns true when [url] is an allowed external URL.
  static bool isAllowed(String url) {
    final uri = _parse(url);
    if (uri == null) return false;
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return false;
    if (!_allowedHosts.contains(uri.host.toLowerCase())) return false;
    return true;
  }

  /// Opens an already-validated [url] in the platform browser.
  ///
  /// Returns true if a browser was launched. Callers must call [isAllowed]
  /// (or [ExternalDestinationRegistry.resolveUrl]) before this.
  static Future<bool> openUrl(String url) async {
    if (!isAllowed(url)) return false;

    final uri = _parse(url);
    if (uri == null) return false;

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Attempts to parse [url] and returns the [Uri] or null.
  static Uri? _parse(String url) {
    try {
      final trimmed = url.trim();
      if (trimmed.isEmpty) return null;
      final uri = Uri.parse(trimmed);
      if (uri.host.isEmpty) return null;
      return uri;
    } catch (_) {
      return null;
    }
  }
}

/// The central registry of named external destinations the AI may request.
///
/// This is the application-side source of truth for external links. The AI
/// never provides the actual URL.
class ExternalDestinationRegistry {
  ExternalDestinationRegistry._();

  static final Map<String, ExternalDestination> _destinations = {
    for (final d in _allDestinations) d.id: d,
  };

  static ExternalDestination? get(String id) => _destinations[id];

  static List<String> get ids => _destinations.keys.toList();

  static bool isRegistered(String id) => _destinations.containsKey(id);

  /// Resolves [id] to a validated URL, or null when the destination is
  /// unknown or its URL is not on the allowlist.
  static String? resolveUrl(String id) {
    final destination = _destinations[id];
    if (destination == null) return null;
    if (!ExternalLinkValidator.isAllowed(destination.url)) return null;
    return destination.url;
  }

  /// True when the current user is allowed to request this external
  /// destination. If [hasPermission] is null, only the permission check is
  /// skipped.
  static bool canAccess(String id, {bool Function(String)? hasPermission}) {
    final destination = _destinations[id];
    if (destination == null) return false;
    if (destination.requiredPermission != null &&
        hasPermission != null &&
        !hasPermission(destination.requiredPermission!)) {
      return false;
    }
    return true;
  }

  static const List<ExternalDestination> _allDestinations = [
    ExternalDestination(
      id: 'official_documentation',
      label: 'Official Documentation',
      url: 'https://pinoypos.app/docs',
      requiredPermission: 'use_ai_advisor',
    ),
    ExternalDestination(
      id: 'support_page',
      label: 'Support Center',
      url: 'https://support.pinoypos.app',
      requiredPermission: 'use_ai_advisor',
    ),
    ExternalDestination(
      id: 'privacy_policy',
      label: 'Privacy Policy',
      url: 'https://pinoypos.app/privacy',
    ),
    ExternalDestination(
      id: 'terms',
      label: 'Terms of Service',
      url: 'https://pinoypos.app/terms',
    ),
    ExternalDestination(
      id: 'groq_documentation',
      label: 'Groq Documentation',
      url: 'https://groq.com/docs',
      requiredPermission: 'manage_ai_config',
    ),
  ];
}
