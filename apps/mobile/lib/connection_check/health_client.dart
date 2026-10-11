import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum HealthFailureKind { timeout, network, unexpectedStatus, invalidResponse }

class HealthCheckException implements Exception {
  const HealthCheckException(this.kind, {this.statusCode});

  final HealthFailureKind kind;
  final int? statusCode;

  String get message => switch (kind) {
    HealthFailureKind.timeout => 'The API did not respond in time.',
    HealthFailureKind.network => 'The API could not be reached.',
    HealthFailureKind.unexpectedStatus =>
      'The API responded with HTTP $statusCode.',
    HealthFailureKind.invalidResponse =>
      'The API returned an unexpected response.',
  };

  @override
  String toString() => 'HealthCheckException($kind, $statusCode)';
}

/// Calls the API liveness endpoint, `GET <baseUrl>/health`.
class HealthClient {
  HealthClient({
    required this.baseUrl,
    required this._httpClient,
    this.timeout = const Duration(seconds: 8),
  });

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _httpClient;

  Uri get healthUrl {
    final prefix = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$prefix/health');
  }

  /// Completes normally only for HTTP 200 with body `{"status": "ok"}` served
  /// directly by [healthUrl]. Every other outcome, including a redirect,
  /// throws [HealthCheckException].
  Future<void> check() async {
    final abort = Completer<void>();
    // Browsers then fail the fetch on a redirect; other clients return the 3xx.
    final request = http.AbortableRequest(
      'GET',
      healthUrl,
      abortTrigger: abort.future,
    )..followRedirects = false;

    final (http.StreamedResponse, List<int>) result;
    try {
      result = await _send(request).timeout(
        timeout,
        onTimeout: () {
          abort.complete();
          throw const HealthCheckException(HealthFailureKind.timeout);
        },
      );
    } on http.ClientException {
      throw const HealthCheckException(HealthFailureKind.network);
    }
    final (response, responseBytes) = result;

    if (response case http.BaseResponseWithUrl(:final url)
        when url != healthUrl) {
      throw const HealthCheckException(HealthFailureKind.invalidResponse);
    }
    if (response.statusCode != 200) {
      throw HealthCheckException(
        HealthFailureKind.unexpectedStatus,
        statusCode: response.statusCode,
      );
    }

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(responseBytes));
    } on FormatException {
      throw const HealthCheckException(HealthFailureKind.invalidResponse);
    }
    if (body is! Map<String, Object?> || body['status'] != 'ok') {
      throw const HealthCheckException(HealthFailureKind.invalidResponse);
    }
  }

  Future<(http.StreamedResponse, List<int>)> _send(
    http.BaseRequest request,
  ) async {
    final response = await _httpClient.send(request);
    return (response, await response.stream.toBytes());
  }
}
