import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum MeFailureKind { unauthorized, unavailable, invalidResponse }

class MeException implements Exception {
  const MeException(this.kind);

  final MeFailureKind kind;

  @override
  String toString() => 'MeException($kind)';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Calls `GET <baseUrl>/api/v1/me` with the caller's access token.
class MeClient {
  MeClient({
    required this.baseUrl,
    required this._httpClient,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _httpClient;

  Uri get meUrl {
    final prefix = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$prefix/api/v1/me');
  }

  /// Returns the server-verified user ID. Throws [MeException] otherwise:
  /// `unauthorized` for 401, `unavailable` for network/timeout/5xx, and
  /// `invalidResponse` for anything else.
  Future<String> fetchUserId(String accessToken) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('GET', meUrl, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $accessToken';

    final (http.StreamedResponse, List<int>) result;
    try {
      result = await _send(request).timeout(
        timeout,
        onTimeout: () {
          abort.complete();
          throw const MeException(MeFailureKind.unavailable);
        },
      );
    } on http.ClientException {
      throw const MeException(MeFailureKind.unavailable);
    }
    final (response, bytes) = result;

    if (response case http.BaseResponseWithUrl(:final url) when url != meUrl) {
      throw const MeException(MeFailureKind.invalidResponse);
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const MeException(MeFailureKind.unauthorized);
      case >= 500:
        throw const MeException(MeFailureKind.unavailable);
      default:
        throw const MeException(MeFailureKind.invalidResponse);
    }

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const MeException(MeFailureKind.invalidResponse);
    }
    if (body case {'user_id': final String userId}
        when _uuid.hasMatch(userId)) {
      return userId;
    }
    throw const MeException(MeFailureKind.invalidResponse);
  }

  Future<(http.StreamedResponse, List<int>)> _send(
    http.BaseRequest request,
  ) async {
    final response = await _httpClient.send(request);
    return (response, await response.stream.toBytes());
  }
}
