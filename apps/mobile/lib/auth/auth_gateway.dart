import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'username.dart';

/// The signed-in user's session as the app needs it. The SDK owns storage and
/// refresh; this is a read-only snapshot.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
  });

  final String userId;
  final String? email;
  final String accessToken;

  String? get username => usernameFromEmail(email);
}

/// A sign-up the provider accepted but that has no session yet, because the
/// project requires email confirmation first.
class ConfirmationRequired implements Exception {
  const ConfirmationRequired();
}

/// The few auth operations the app uses. The real implementation delegates to
/// the Supabase SDK; widget tests substitute a fake.
abstract interface class AuthGateway {
  AuthSession? get currentSession;

  /// Emits the current session (or null) whenever it changes.
  Stream<AuthSession?> get sessionChanges;

  /// Creates an account and signs it in. Throws [ConfirmationRequired] if the
  /// provider requires email confirmation before the first sign-in.
  Future<void> signUp({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  /// Asks the provider for fresh tokens; returns the new session, or null.
  Future<AuthSession?> refresh();

  /// Clears the local session immediately, then ends it on the server.
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final sb.GoTrueClient _client;

  static AuthSession? _toSession(sb.Session? session) => session == null
      ? null
      : AuthSession(
          userId: session.user.id,
          email: session.user.email,
          accessToken: session.accessToken,
        );

  @override
  AuthSession? get currentSession => _toSession(_client.currentSession);

  @override
  Stream<AuthSession?> get sessionChanges =>
      _client.onAuthStateChange.map((state) => _toSession(state.session));

  @override
  Future<void> signUp({required String email, required String password}) async {
    final response = await _client.signUp(email: email, password: password);
    if (response.session == null) throw const ConfirmationRequired();
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _client.signInWithPassword(email: email, password: password);

  @override
  Future<AuthSession?> refresh() async =>
      _toSession((await _client.refreshSession()).session);

  /// Local scope: ends this device's session; other devices stay signed in.
  @override
  Future<void> signOut() => _client.signOut(scope: sb.SignOutScope.local);
}
