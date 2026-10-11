import '../auth/auth_controller.dart';
import 'idea.dart';
import 'ideas_client.dart';

/// The signed-in identity changed while a request was running; its result
/// belongs to the previous session and must be dropped.
class SessionChanged implements Exception {
  const SessionChanged();
}

/// The session could not be refreshed; the user must sign in again.
class SessionExpired implements Exception {
  const SessionExpired();
}

/// Idea operations for the current session. On a 401 the session is
/// refreshed once and the same request is retried once.
class IdeasRepository {
  IdeasRepository({required this.controller, required this.client});

  final AuthController controller;
  final IdeasClient client;

  Future<T> _authorized<T>(Future<T> Function(String token) call) async {
    final generation = controller.generation;
    void checkSession() {
      if (controller.generation != generation) throw const SessionChanged();
    }

    final token = controller.session?.accessToken;
    if (token == null) throw const SessionChanged();
    try {
      final result = await call(token);
      checkSession();
      return result;
    } on IdeasException catch (error) {
      checkSession();
      if (error.kind != IdeasFailureKind.unauthorized) rethrow;
    }

    String? refreshed;
    try {
      refreshed = await controller.refreshAccessToken();
    } catch (_) {
      refreshed = null;
    }
    checkSession();
    if (refreshed == null) throw const SessionExpired();
    try {
      final result = await call(refreshed);
      checkSession();
      return result;
    } on IdeasException catch (error) {
      checkSession();
      if (error.kind == IdeasFailureKind.unauthorized) {
        throw const SessionExpired();
      }
      rethrow;
    }
  }

  Future<IdeaPage> list({String? cursor, String? category}) => _authorized(
    (token) => client.list(token, cursor: cursor, category: category),
  );

  Future<Idea> get(String id) => _authorized((token) => client.get(token, id));

  Future<Idea> create({required IdeaFields fields, String? originalText}) =>
      _authorized(
        (token) =>
            client.create(token, fields: fields, originalText: originalText),
      );

  Future<Idea> update(String id, IdeaFields fields) =>
      _authorized((token) => client.update(token, id, fields));

  Future<void> delete(String id) =>
      _authorized((token) => client.delete(token, id));
}
