/// Public build-time configuration. Every value compiled into the web app is
/// visible to anyone who loads it, so never put secrets here.
library;

/// Raw `API_BASE_URL` supplied with `--dart-define` or
/// `--dart-define-from-file`.
const String apiBaseUrlDefine = String.fromEnvironment('API_BASE_URL');

/// Parses the API origin (optionally with a path prefix).
///
/// Throws [FormatException] for anything other than an absolute http(s) URL
/// so a missing or mistyped build setting is reported instead of guessed.
Uri parseApiBaseUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException(
      'API_BASE_URL is not set. Build with --dart-define-from-file=config/development.json '
      'or --dart-define=API_BASE_URL=<url>.',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw FormatException(
      'API_BASE_URL must be an absolute http(s) URL such as http://localhost:8000.',
      value,
    );
  }
  return uri;
}
