import 'ideas_client.dart';
import 'ideas_repository.dart';

/// Plain-language text for a failed idea request.
String describeIdeasFailure(Object error) => switch (error) {
  SessionExpired() => 'Your session has expired. Please sign in again.',
  IdeasException(kind: IdeasFailureKind.unavailable) =>
    'Could not reach the server. Check your connection and try again.',
  IdeasException(kind: IdeasFailureKind.notFound) =>
    'This idea no longer exists.',
  IdeasException(kind: IdeasFailureKind.tooLarge) =>
    'This idea is too large to save. Shorten the longest text.',
  IdeasException(kind: IdeasFailureKind.invalid) =>
    'Some values could not be saved. Check the fields and try again.',
  _ => 'Something went wrong. Please try again.',
};
