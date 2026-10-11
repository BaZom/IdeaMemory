import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/auth/auth_gateway.dart';
import 'package:mobile/ideas/ideas_client.dart';

const userA = AuthSession(
  userId: '11111111-1111-4111-8111-111111111111',
  email: 'alice@users.invalid',
  accessToken: 'token-a',
);
const userB = AuthSession(
  userId: '22222222-2222-4222-8222-222222222222',
  email: 'bob@users.invalid',
  accessToken: 'token-b',
);

/// Auth gateway whose every operation completes only when the test says so.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway([this._session]);

  final _changes = StreamController<AuthSession?>.broadcast(sync: true);
  AuthSession? _session;

  final signUpCalls = <(String, String)>[];
  final signInCalls = <(String, String)>[];
  int refreshCalls = 0;
  int signOutCalls = 0;

  Completer<void>? pendingSignUp;
  Completer<void>? pendingSignIn;
  Completer<AuthSession?>? pendingRefresh;
  Completer<void>? pendingSignOut;

  /// Simulates the SDK reporting a session change.
  void emit(AuthSession? session) {
    _session = session;
    _changes.add(session);
  }

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> signUp({required String email, required String password}) {
    signUpCalls.add((email, password));
    return (pendingSignUp = Completer<void>()).future;
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    signInCalls.add((email, password));
    return (pendingSignIn = Completer<void>()).future;
  }

  @override
  Future<AuthSession?> refresh() {
    refreshCalls++;
    return (pendingRefresh = Completer<AuthSession?>()).future;
  }

  @override
  Future<void> signOut() {
    signOutCalls++;
    // Like the SDK: the local session is cleared before the server call.
    emit(null);
    return (pendingSignOut = Completer<void>()).future;
  }
}

/// API whose `/api/v1/ideas` responses are completed by the test, per request.
class FakeIdeasApi {
  FakeIdeasApi({this.answerListsEmpty = false});

  /// Answers every list request at once with an empty collection.
  final bool answerListsEmpty;
  final requests = <http.Request>[];
  final _pending = <Completer<http.Response>>[];

  IdeasClient client() => IdeasClient(
    baseUrl: Uri.parse('http://api.test:8000'),
    httpClient: MockClient((request) {
      requests.add(request);
      final completer = Completer<http.Response>();
      _pending.add(completer);
      if (answerListsEmpty &&
          request.method == 'GET' &&
          request.url.path == '/api/v1/ideas') {
        completer.complete(_json(200, {'items': [], 'next_cursor': null}));
      }
      return completer.future;
    }),
  );

  http.Request get last => requests.last;
  int get count => requests.length;

  Object? bodyOf(int index) => jsonDecode(requests[index].body);

  String? tokenOf(int index) =>
      requests[index].headers['Authorization']?.replaceFirst('Bearer ', '');

  bool isPending(int index) => !_pending[index].isCompleted;

  void respond(int index, int status, [Object? body]) =>
      _pending[index].complete(_json(status, body));

  void respondError(int index, int status, String code) =>
      respond(index, status, {
        'error': {'code': code, 'message': 'x'},
      });

  void fail(int index) =>
      _pending[index].completeError(http.ClientException('offline'));

  static http.Response _json(int status, Object? body) => http.Response.bytes(
    body == null ? const [] : utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// An idea as the API returns it.
Map<String, Object?> ideaJson({
  String id = 'aaaaaaaa-0000-4000-8000-000000000001',
  String title = 'Ramen',
  String? description,
  String? notes,
  String? location,
  String? category,
  List<String> tags = const [],
  List<Map<String, Object?>>? sources = const [],
  String createdAt = '2026-10-11T10:00:00.000000Z',
  String? updatedAt,
}) => {
  'id': id,
  'title': title,
  'description': description,
  'notes': notes,
  'location': location,
  'category': category,
  'tags': tags,
  'created_at': createdAt,
  'updated_at': updatedAt ?? createdAt,
  'sources': ?sources,
};

Map<String, Object?> textSource(String text) => {
  'id': 'bbbbbbbb-0000-4000-8000-000000000001',
  'kind': 'text',
  'original_text': text,
  'created_at': '2026-10-11T10:00:00.000000Z',
};
