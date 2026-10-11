/// Public build-time configuration. Every value compiled into the web app is
/// visible to anyone who loads it, so never put secrets here.
library;

import 'dart:convert';

/// Raw values supplied with `--dart-define` or `--dart-define-from-file`.
const String apiBaseUrlDefine = String.fromEnvironment('API_BASE_URL');
const String supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
const String supabasePublishableKeyDefine = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

const _configHint =
    'Build with --dart-define-from-file=config/development.json or matching '
    '--dart-define values.';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  /// Parses all public settings, throwing [FormatException] on the first
  /// missing or invalid value.
  factory AppConfig.parse({
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabasePublishableKey,
  }) => AppConfig(
    apiBaseUrl: parseApiBaseUrl(apiBaseUrl),
    supabaseUrl: _parseHttpUrl('SUPABASE_URL', supabaseUrl),
    supabasePublishableKey: parsePublishableKey(supabasePublishableKey),
  );

  factory AppConfig.fromEnvironment() => AppConfig.parse(
    apiBaseUrl: apiBaseUrlDefine,
    supabaseUrl: supabaseUrlDefine,
    supabasePublishableKey: supabasePublishableKeyDefine,
  );

  final Uri apiBaseUrl;
  final Uri supabaseUrl;
  final String supabasePublishableKey;
}

/// Parses the API origin (optionally with a path prefix).
///
/// Throws [FormatException] for anything other than an absolute http(s) URL
/// so a missing or mistyped build setting is reported instead of guessed.
Uri parseApiBaseUrl(String raw) => _parseHttpUrl('API_BASE_URL', raw);

Uri _parseHttpUrl(String name, String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    throw FormatException('$name is not set. $_configHint');
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw FormatException(
      '$name must be an absolute http(s) URL such as http://localhost:8000.',
      value,
    );
  }
  return uri;
}

/// Accepts a public Supabase key and refuses anything that looks privileged,
/// because every build-time value ships to the browser.
String parsePublishableKey(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    throw FormatException('SUPABASE_PUBLISHABLE_KEY is not set. $_configHint');
  }
  if (value.startsWith('sb_secret_') || _isNonAnonJwt(value)) {
    throw const FormatException(
      'SUPABASE_PUBLISHABLE_KEY contains a secret key. Use the publishable '
      '(or legacy anon) key; secret keys must never be built into the app.',
    );
  }
  return value;
}

bool _isNonAnonJwt(String value) {
  final parts = value.split('.');
  if (parts.length != 3) return false;
  try {
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return claims is Map && claims['role'] != 'anon';
  } on FormatException {
    return false;
  }
}
