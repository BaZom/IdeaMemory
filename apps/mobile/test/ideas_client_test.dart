import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/ideas/idea.dart';
import 'package:mobile/ideas/ideas_client.dart';

import 'fakes.dart';

IdeasClient _client(
  Future<http.Response> Function(http.Request) handler, {
  String base = 'http://api.test:8000',
  Duration timeout = const Duration(seconds: 15),
}) => IdeasClient(
  baseUrl: Uri.parse(base),
  httpClient: MockClient(handler),
  timeout: timeout,
);

http.Response _json(int status, Object? body) =>
    http.Response(jsonEncode(body), status);

Matcher _fails(IdeasFailureKind kind, [String? code]) => throwsA(
  isA<IdeasException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.code, 'code', code),
);

void main() {
  test('create sends the token and the fields', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json(201, ideaJson(sources: [textSource(' exact ')]));
    });

    final idea = await client.create(
      'token-a',
      fields: const IdeaFields(title: 'Ramen', tags: ['a']),
      originalText: ' exact ',
    );

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://api.test:8000/api/v1/ideas');
    expect(sent.headers['Authorization'], 'Bearer token-a');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {
      'title': 'Ramen',
      'description': null,
      'notes': null,
      'location': null,
      'category': null,
      'tags': ['a'],
      'original_text': ' exact ',
    });
    expect(sent.followRedirects, isFalse);
    expect(idea.sources!.single.originalText, ' exact ');
  });

  test('create omits original text when there is none', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json(200, ideaJson());
    });

    await client.create('t', fields: const IdeaFields(title: 'x'));

    expect(
      (jsonDecode(sent.body) as Map).containsKey('original_text'),
      isFalse,
    );
  });

  test('list passes the cursor and keeps a path prefix', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json(200, {
        'items': [ideaJson(sources: null)],
        'next_cursor': 'next',
      });
    }, base: 'https://example.test/prefix/');

    final page = await client.list('t', cursor: 'abc/=+');

    expect(sent.url.path, '/prefix/api/v1/ideas');
    expect(sent.url.queryParameters, {'limit': '20', 'cursor': 'abc/=+'});
    expect(page.nextCursor, 'next');
    expect(page.items.single.sources, isNull);
  });

  test('update sends all fields; delete has no body', () async {
    final sent = <http.Request>[];
    final client = _client((request) async {
      sent.add(request);
      return request.method == 'DELETE'
          ? http.Response('', 204)
          : _json(200, ideaJson());
    });

    await client.update('t', 'id-1', const IdeaFields(title: 'New'));
    await client.delete('t', 'id-1');

    expect(sent[0].method, 'PATCH');
    expect(sent[0].url.path, '/api/v1/ideas/id-1');
    expect(jsonDecode(sent[0].body), {
      'title': 'New',
      'description': null,
      'notes': null,
      'location': null,
      'category': null,
      'tags': <Object?>[],
    });
    expect(sent[1].method, 'DELETE');
    expect(sent[1].url.path, '/api/v1/ideas/id-1');
    expect(sent[1].body, isEmpty);
  });

  group('failures', () {
    for (final (status, kind) in [
      (401, IdeasFailureKind.unauthorized),
      (404, IdeasFailureKind.notFound),
      (422, IdeasFailureKind.invalid),
      (503, IdeasFailureKind.unavailable),
    ]) {
      test('$status is $kind with the server code', () {
        final client = _client(
          (_) async => _json(status, {
            'error': {'code': 'some_code', 'message': 'x'},
          }),
        );
        expect(client.get('t', 'id'), _fails(kind, 'some_code'));
      });
    }

    test('timeouts are unavailable', () {
      final client = _client(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(client.list('t'), _fails(IdeasFailureKind.unavailable));
    });

    test('malformed success bodies are invalid responses', () {
      for (final body in ['not json', '{"id": 1}']) {
        final client = _client((_) async => http.Response(body, 200));
        expect(client.get('t', 'id'), _fails(IdeasFailureKind.invalidResponse));
      }
    });
  });
}
