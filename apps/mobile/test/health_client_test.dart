import 'dart:async';

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

  for (final status in [201, 204, 301, 404, 500, 503]) {
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
