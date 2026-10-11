import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/connection_check/health_client.dart';

HealthClient _client(
  MockClientHandler handler, {
  String baseUrl = 'http://api.test:8000',
  Duration timeout = const Duration(seconds: 8),
}) => HealthClient(
  baseUrl: Uri.parse(baseUrl),
  httpClient: MockClient(handler),
  timeout: timeout,
);

/// A response that reports its final URL, as browser and IO clients do.
class _ResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _ResponseWithUrl(super.stream, super.statusCode, {required this.url});

  @override
  final Uri url;
}

/// Returns a 200 `{"status":"ok"}` whose reported final URL is [finalUrl], or
/// the requested URL when null. (MockClient drops the URL.)
class _FinalUrlClient extends http.BaseClient {
  _FinalUrlClient([this.finalUrl]);

  final Uri? finalUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _ResponseWithUrl(
        Stream.value(utf8.encode('{"status":"ok"}')),
        200,
        url: finalUrl ?? request.url,
      );
}

Matcher _failsWith(HealthFailureKind kind, {int? statusCode}) => throwsA(
  isA<HealthCheckException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.statusCode, 'statusCode', statusCode),
);

void main() {
  test('GETs <baseUrl>/health and succeeds on the exact contract', () async {
    late http.Request seen;
    final client = _client((request) async {
      seen = request;
      return http.Response('{"status":"ok"}', 200);
    });

    await client.check();

    expect(seen.method, 'GET');
    expect(seen.url, Uri.parse('http://api.test:8000/health'));
    expect(seen.followRedirects, isFalse);
  });

  test('keeps a configured path prefix', () {
    final withSlash = _client(
      (_) async => http.Response('', 200),
      baseUrl: 'https://example.test/api/',
    );
    final withoutSlash = _client(
      (_) async => http.Response('', 200),
      baseUrl: 'https://example.test/api',
    );

    expect(withSlash.healthUrl, Uri.parse('https://example.test/api/health'));
    expect(
      withoutSlash.healthUrl,
      Uri.parse('https://example.test/api/health'),
    );
  });

  for (final status in [201, 204, 404, 500, 503]) {
    test('HTTP $status is a failure even with an ok body', () {
      final client = _client(
        (_) async => http.Response('{"status":"ok"}', status),
      );

      expect(
        client.check(),
        _failsWith(HealthFailureKind.unexpectedStatus, statusCode: status),
      );
    });
  }

  for (final body in [
    '',
    'ok',
    '<html></html>',
    '{"status":"ok"',
    '[]',
    '"ok"',
    '{}',
    '{"status":"down"}',
    '{"status":true}',
    '{"state":"ok"}',
  ]) {
    test('invalid body ${body.isEmpty ? '(empty)' : body} is a failure', () {
      final client = _client((_) async => http.Response(body, 200));

      expect(client.check(), _failsWith(HealthFailureKind.invalidResponse));
    });
  }

  for (final status in [301, 302, 307, 308]) {
    test('unfollowed HTTP $status redirect is a failure', () {
      final client = _client(
        (_) async => http.Response(
          '{"status":"ok"}',
          status,
          headers: {'location': 'http://elsewhere.test/health'},
        ),
      );

      expect(
        client.check(),
        _failsWith(HealthFailureKind.unexpectedStatus, statusCode: status),
      );
    });
  }

  test('a response from a redirected URL is a failure', () {
    final client = HealthClient(
      baseUrl: Uri.parse('http://api.test:8000'),
      httpClient: _FinalUrlClient(Uri.parse('http://elsewhere.test/health')),
    );

    expect(client.check(), _failsWith(HealthFailureKind.invalidResponse));
  });

  test('a response reporting the requested URL succeeds', () async {
    final client = HealthClient(
      baseUrl: Uri.parse('http://api.test:8000'),
      httpClient: _FinalUrlClient(),
    );

    await client.check();
  });

  test('a redirect refused by the browser is a failure', () {
    final client = _client(
      (_) async => throw http.ClientException('redirect not allowed'),
    );

    expect(client.check(), _failsWith(HealthFailureKind.network));
  });

  test('invalid UTF-8 body is a failure', () {
    final client = _client(
      (_) async => http.Response.bytes([0x7b, 0xff, 0xfe, 0x7d], 200),
    );

    expect(client.check(), _failsWith(HealthFailureKind.invalidResponse));
  });

  test('network errors are failures', () {
    final client = _client(
      (_) async => throw http.ClientException('connection refused'),
    );

    expect(client.check(), _failsWith(HealthFailureKind.network));
  });

  test('a slow response times out and aborts the request', () async {
    final aborted = Completer<void>();
    final client = HealthClient(
      baseUrl: Uri.parse('http://api.test:8000'),
      httpClient: MockClient.streaming((request, _) {
        (request as http.Abortable).abortTrigger!.then(
          (_) => aborted.complete(),
        );
        return Completer<http.StreamedResponse>().future;
      }),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(client.check(), _failsWith(HealthFailureKind.timeout));
    await aborted.future.timeout(const Duration(seconds: 1));
  });
}
