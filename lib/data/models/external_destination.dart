/// A trusted, application-registered external destination.
///
/// The AI may request an external link by [id], but the application—not the
/// model—resolves the final [url]. This prevents arbitrary AI-generated URLs
/// from being opened.
class ExternalDestination {
  final String id;
  final String label;
  final String url;
  final String? requiredPermission;

  const ExternalDestination({
    required this.id,
    required this.label,
    required this.url,
    this.requiredPermission,
  });
}
