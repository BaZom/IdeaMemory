import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/account/me_client.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

MeClient _client(
  MockClientHandler handler, {
  Duration timeout = const Duration(seconds: 10),
}) => MeClient(
  baseUrl: Uri.parse('http://api.test:8000'),
  httpClient: MockClient(handler),
  timeout: timeout,
);

Matcher _failsWith(MeFailureKind kind) =>
    throwsA(isA<MeException>().having((e) => e.kind, 'kind', kind));

class _ResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _ResponseWithUrl(super.stream, super.statusCode, {required this.url});

  @override
  final Uri url;
}

class _RedirectedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _ResponseWithUrl(
        Stream.value(utf8.encode('{"user_id":"$_userId"}')),
        200,
        url: Uri.parse('http://elsewhere.test/api/v1/me'),
      );
}

void main() {
  test('sends the bearer token and returns the verified user ID', () async {
    late http.Request seen;
    final client = _client((request) async {
      seen = request;
      return http.Response('{"user_id":"$_userId"}', 200);
    });

    expect(await client.fetchUserId('token-a'), _userId);
    expect(seen.method, 'GET');
    expect(seen.url, Uri.parse('http://api.test:8000/api/v1/me'));
    expect(seen.headers['Authorization'], 'Bearer token-a');
    expect(seen.followRedirects, isFalse);
  });

  test('401 is unauthorized', () {
    final client = _client((_) async => http.Response('{}', 401));
    expect(client.fetchUserId('t'), _failsWith(MeFailureKind.unauthorized));
  });

  for (final status in [500, 502, 503]) {
    test('$status is unavailable', () {
      final client = _client((_) async => http.Response('', status));
      expect(client.fetchUserId('t'), _failsWith(MeFailureKind.unavailable));
    });
  }

  for (final status in [201, 204, 302, 400, 403, 404]) {
    test('$status is an invalid response', () {
      final client = _client(
        (_) async => http.Response('{"user_id":"$_userId"}', status),
      );
      expect(
        client.fetchUserId('t'),
        _failsWith(MeFailureKind.invalidResponse),
      );
    });
  }

  for (final body in [
    '',
    'not json',
    '[]',
    '{}',
    '{"user_id":null}',
    '{"user_id":42}',
    '{"user_id":"not-a-uuid"}',
    '{"user_id":"${_userId.toUpperCase()}x"}',
  ]) {
    test('body ${body.isEmpty ? '(empty)' : body} is invalid', () {
      final client = _client((_) async => http.Response(body, 200));
      expect(
        client.fetchUserId('t'),
        _failsWith(MeFailureKind.invalidResponse),
      );
    });
  }

  test('a response from a redirected URL is invalid', () {
    final client = MeClient(
      baseUrl: Uri.parse('http://api.test:8000'),
      httpClient: _RedirectedClient(),
    );
    expect(client.fetchUserId('t'), _failsWith(MeFailureKind.invalidResponse));
  });

  test('network errors are unavailable', () {
    final client = _client((_) async => throw http.ClientException('down'));
    expect(client.fetchUserId('t'), _failsWith(MeFailureKind.unavailable));
  });

  test('timeouts are unavailable', () {
    final client = _client(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 20),
    );
    expect(client.fetchUserId('t'), _failsWith(MeFailureKind.unavailable));
  });
}
