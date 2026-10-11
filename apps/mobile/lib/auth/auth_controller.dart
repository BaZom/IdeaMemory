import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_gateway.dart';
import 'username.dart';

/// App-wide session state on top of the SDK's managed session.
///
/// [generation] changes whenever the signed-in identity changes (sign-in,
/// sign-out or a different user), so async work started for one session can
/// detect that it no longer applies and drop its result.
class AuthController extends ChangeNotifier {
  AuthController(this._gateway) : _session = _gateway.currentSession {
    _subscription = _gateway.sessionChanges.listen(
      _apply,
      // Refresh failures surface as stream errors; the SDK then reports the
      // resulting session (if any) as a normal event.
      onError: (Object _) {},
    );
  }

  final AuthGateway _gateway;
  late final StreamSubscription<AuthSession?> _subscription;
  AuthSession? _session;
  int _generation = 0;
  bool _signingOut = false;
  bool _remoteSignOutFailed = false;

  AuthSession? get session => _session;
  int get generation => _generation;
  bool get isSigningOut => _signingOut;

  /// True after a sign-out that cleared this device but could not reach the
  /// server to end the session there.
  bool get remoteSignOutFailed => _remoteSignOutFailed;

  void _apply(AuthSession? next) {
    final previous = _session;
    _session = next;
    if (previous?.userId != next?.userId) {
      _generation++;
      if (next != null) _remoteSignOutFailed = false;
    }
    notifyListeners();
  }

  /// [username] must already be normalised and valid (see username.dart).
  Future<void> signUp({required String username, required String password}) =>
      _gateway.signUp(email: usernameToEmail(username), password: password);

  Future<void> signIn({required String username, required String password}) =>
      _gateway.signIn(email: usernameToEmail(username), password: password);

  /// Returns a fresh access token for the current identity, or null if the
  /// session could not be refreshed or the identity changed meanwhile.
  Future<String?> refreshAccessToken() async {
    final generation = _generation;
    final refreshed = await _gateway.refresh();
    if (generation != _generation) return null;
    return refreshed?.accessToken;
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    _remoteSignOutFailed = false;
    // Private UI disappears on the SDK's immediate signed-out event; this
    // also covers the case where no event arrives.
    _apply(null);
    try {
      await _gateway.signOut();
    } catch (_) {
      _remoteSignOutFailed = true;
    } finally {
      _signingOut = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
