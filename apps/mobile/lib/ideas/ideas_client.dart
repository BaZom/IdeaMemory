import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'idea.dart';

enum IdeasFailureKind {
  /// 401: the token was refused.
  unauthorized,

  /// 404: missing, or not this user's.
  notFound,

  /// 422: the server refused the values.
  invalid,

  /// 413: the request body is too large.
  tooLarge,

  /// Network failure, timeout or 5xx. The outcome of a write is unknown.
  unavailable,

  /// Anything else, including malformed responses.
  invalidResponse,
}

class IdeasException implements Exception {
  const IdeasException(this.kind, [this.code]);

  final IdeasFailureKind kind;

  /// The API's error code, e.g. `idea_not_found`, when one was returned.
  final String? code;

  @override
  String toString() => 'IdeasException($kind, $code)';
}

/// Calls `<baseUrl>/api/v1/ideas` with the caller's access token.
class IdeasClient {
  IdeasClient({
    required this.baseUrl,
    required this._httpClient,
    this.timeout = const Duration(seconds: 15),
  });

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _httpClient;

  Uri _url(List<String> segments, [Map<String, String>? query]) {
    final prefix = baseUrl.pathSegments.where((s) => s.isNotEmpty);
    return baseUrl.replace(
      pathSegments: [...prefix, 'api', 'v1', 'ideas', ...segments],
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<IdeaPage> list(String token, {String? cursor, int limit = 20}) async {
    final body = await _send(
      'GET',
      _url([], {'limit': '$limit', 'cursor': ?cursor}),
      token,
    );
    if (body
        case {'items': final List<Object?> items, 'next_cursor': final next}
        when next == null || next is String) {
      return _parsing(
        () => IdeaPage(
          items: [
            for (final item in items) Idea.fromJson(item, withSources: false),
          ],
          nextCursor: next as String?,
        ),
      );
    }
    throw const IdeasException(IdeasFailureKind.invalidResponse);
  }

  Future<Idea> get(String token, String id) async =>
      _idea(await _send('GET', _url([id]), token));

  Future<Idea> create(
    String token, {
    required IdeaFields fields,
    String? originalText,
  }) async => _idea(
    await _send(
      'POST',
      _url([]),
      token,
      body: {...fields.toJson(), 'original_text': ?originalText},
    ),
  );

  /// Saves [fields] over the idea; the last save wins.
  Future<Idea> update(String token, String id, IdeaFields fields) async =>
      _idea(await _send('PATCH', _url([id]), token, body: fields.toJson()));

  Future<void> delete(String token, String id) async {
    await _send('DELETE', _url([id]), token);
  }

  Idea _idea(Object? body) =>
      _parsing(() => Idea.fromJson(body, withSources: true));

  T _parsing<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw const IdeasException(IdeasFailureKind.invalidResponse);
    }
  }

  /// Returns the decoded JSON body of a 2xx response (null for 204).
  Future<Object?> _send(
    String method,
    Uri url,
    String token, {
    Object? body,
  }) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final (http.StreamedResponse, List<int>) result;
    try {
      result = await _read(request).timeout(
        timeout,
        onTimeout: () {
          abort.complete();
          throw const IdeasException(IdeasFailureKind.unavailable);
        },
      );
    } on http.ClientException {
      throw const IdeasException(IdeasFailureKind.unavailable);
    }
    final (response, bytes) = result;
    if (response case http.BaseResponseWithUrl(:final url)
        when url != request.url) {
      throw const IdeasException(IdeasFailureKind.invalidResponse);
    }

    Object? decoded;
    if (bytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        decoded = null;
      }
    }
    final status = response.statusCode;
    if (status == 204) return null;
    if (status >= 200 && status < 300) {
      if (decoded == null) {
        throw const IdeasException(IdeasFailureKind.invalidResponse);
      }
      return decoded;
    }
    final code = switch (decoded) {
      {'error': {'code': final String code}} => code,
      _ => null,
    };
    throw IdeasException(switch (status) {
      401 => IdeasFailureKind.unauthorized,
      404 => IdeasFailureKind.notFound,
      413 => IdeasFailureKind.tooLarge,
      422 => IdeasFailureKind.invalid,
      >= 500 => IdeasFailureKind.unavailable,
      _ => IdeasFailureKind.invalidResponse,
    }, code);
  }

  Future<(http.StreamedResponse, List<int>)> _read(
    http.BaseRequest request,
  ) async {
    final response = await _httpClient.send(request);
    return (response, await response.stream.toBytes());
  }
}
