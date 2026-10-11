import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/account/me_client.dart';
import 'package:mobile/auth/auth_gateway.dart';

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

/// API whose `/api/v1/me` responses are completed by the test, per request.
class FakeMeApi {
  final requests = <http.Request>[];
  final _pending = <Completer<http.Response>>[];

  MeClient client() => MeClient(
    baseUrl: Uri.parse('http://api.test:8000'),
    httpClient: MockClient((request) {
      requests.add(request);
      final completer = Completer<http.Response>();
      _pending.add(completer);
      return completer.future;
    }),
  );

  String? tokenOf(int index) =>
      requests[index].headers['Authorization']?.replaceFirst('Bearer ', '');

  void respond(int index, int status, [String body = '']) =>
      _pending[index].complete(http.Response(body, status));

  void respondUser(int index, AuthSession user) =>
      respond(index, 200, '{"user_id":"${user.userId}"}');
}
