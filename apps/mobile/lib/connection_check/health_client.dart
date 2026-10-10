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

  /// Completes normally only for HTTP 200 with body `{"status": "ok"}`.
  /// Every other outcome throws [HealthCheckException].
  Future<void> check() async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      healthUrl,
      abortTrigger: abort.future,
    );

    final http.Response response;
    try {
      response = await _send(request).timeout(
        timeout,
        onTimeout: () {
          abort.complete();
          throw const HealthCheckException(HealthFailureKind.timeout);
        },
      );
    } on http.ClientException {
      throw const HealthCheckException(HealthFailureKind.network);
    }

    if (response.statusCode != 200) {
      throw HealthCheckException(
        HealthFailureKind.unexpectedStatus,
        statusCode: response.statusCode,
      );
    }

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const HealthCheckException(HealthFailureKind.invalidResponse);
    }
    if (body is! Map<String, Object?> || body['status'] != 'ok') {
      throw const HealthCheckException(HealthFailureKind.invalidResponse);
    }
  }

  Future<http.Response> _send(http.BaseRequest request) async =>
      http.Response.fromStream(await _httpClient.send(request));
}
