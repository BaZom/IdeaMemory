import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/auth/auth_controller.dart';
import 'package:mobile/auth/auth_gate.dart';
import 'package:mobile/auth/auth_gateway.dart';
import 'package:mobile/auth/sign_in_page.dart' show AuthMode;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthRetryableFetchException;

import 'fakes.dart';

final _submitSignIn = find.widgetWithText(FilledButton, 'Sign in');
final _submitSignUp = find.widgetWithText(FilledButton, 'Create account');
final _signOut = find.widgetWithText(OutlinedButton, 'Sign out');
final _usernameField = find.widgetWithText(TextField, 'Username');
final _passwordField = find.widgetWithText(TextField, 'Password');
final _signUpTab = find.widgetWithText(SegmentedButton<AuthMode>, 'Sign up');

class _Harness {
  _Harness([AuthSession? session])
    : gateway = FakeAuthGateway(session),
      api = FakeMeApi() {
    controller = AuthController(gateway);
  }

  final FakeAuthGateway gateway;
  final FakeMeApi api;
  late final AuthController controller;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ShellApp(
        home: AuthGate(controller: controller, meClient: api.client()),
      ),
    );
    addTearDown(controller.dispose);
  }
}

/// Lets unanswered API requests reach their timeout so no timer outlives
/// the test.
Future<void> _drainTimeouts(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 11));

Future<void> _fill(
  WidgetTester tester,
  String username,
  String password,
) async {
  await tester.enterText(_usernameField, username);
  await tester.enterText(_passwordField, password);
}

void main() {
  group('sign-in', () {
    testWidgets('starts in sign-in mode with a sign-up choice', (tester) async {
      await _Harness().pump(tester);

      expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
      expect(_usernameField, findsOneWidget);
      expect(_passwordField, findsOneWidget);
      expect(_signUpTab, findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<AuthMode>>(
              find.byType(SegmentedButton<AuthMode>),
            )
            .selected,
        {AuthMode.signIn},
      );
      expect(tester.widget<TextField>(_passwordField).obscureText, isTrue);
    });

    testWidgets('validates input without calling the provider', (tester) async {
      final h = _Harness();
      await h.pump(tester);

      await _fill(tester, 'a b', 'whatever1');
      await tester.tap(_submitSignIn);
      await tester.pump();
      expect(
        find.text(
          'Use letters, numbers, dots, dashes or underscores, starting with a '
          'letter or number.',
        ),
        findsOneWidget,
      );

      await _fill(tester, 'alice', '');
      await tester.tap(_submitSignIn);
      await tester.pump();
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(h.gateway.signInCalls, isEmpty);
    });

    testWidgets('signs in with username and password', (tester) async {
      final h = _Harness();
      await h.pump(tester);

      await _fill(tester, ' Alice ', 'Correct-horse-1');
      await tester.tap(_submitSignIn);
      await tester.tap(_submitSignIn, warnIfMissed: false);
      await tester.pump();
      expect(h.gateway.signInCalls, [
        ('alice@users.invalid', 'Correct-horse-1'),
      ]);

      h.gateway.emit(userA);
      h.gateway.pendingSignIn!.complete();
      await tester.pump();
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('users.invalid'), findsNothing);
      h.api.respondUser(0, userA);
      await tester.pump();
      expect(find.text('User ID: ${userA.userId}'), findsOneWidget);
    });

    testWidgets('wrong credentials show one neutral message', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _fill(tester, 'alice', 'wrong-password');
      await tester.tap(_submitSignIn);
      await tester.pump();

      h.gateway.pendingSignIn!.completeError(
        const AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );
      await tester.pump();

      expect(find.text('Username or password is incorrect.'), findsOneWidget);
      expect(find.textContaining('Invalid login'), findsNothing);
      expect(h.controller.session, isNull);
    });

    testWidgets('network failure allows retry', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _fill(tester, 'alice', 'Correct-horse-1');
      await tester.tap(_submitSignIn);
      await tester.pump();
      h.gateway.pendingSignIn!.completeError(AuthRetryableFetchException());
      await tester.pump();

      expect(
        find.text(
          'Could not reach the sign-in service. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(_submitSignIn);
      await tester.pump();
      expect(h.gateway.signInCalls, hasLength(2));
    });

    testWidgets('rate limiting shows a wait message', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _fill(tester, 'alice', 'Correct-horse-1');
      await tester.tap(_submitSignIn);
      await tester.pump();
      h.gateway.pendingSignIn!.completeError(
        const AuthApiException(
          'Request rate limit reached',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      );
      await tester.pump();

      expect(
        find.text('Too many attempts. Please wait a minute and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('password can be revealed and hidden', (tester) async {
      await _Harness().pump(tester);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(_passwordField).obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(tester.widget<TextField>(_passwordField).obscureText, isTrue);
    });
  });

  group('sign-up', () {
    Future<_Harness> startSignUp(WidgetTester tester) async {
      final h = _Harness();
      await h.pump(tester);
      await tester.tap(_signUpTab);
      await tester.pump();
      return h;
    }

    testWidgets('sign-up mode explains the password rule', (tester) async {
      await startSignUp(tester);

      expect(find.widgetWithText(AppBar, 'Create account'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(_submitSignUp, findsOneWidget);
    });

    testWidgets('short password is rejected locally', (tester) async {
      final h = await startSignUp(tester);

      await _fill(tester, 'newbie', 'short');
      await tester.tap(_submitSignUp);
      await tester.pump();

      expect(
        find.text('Choose a password with at least 8 characters.'),
        findsOneWidget,
      );
      expect(h.gateway.signUpCalls, isEmpty);
    });

    testWidgets('new user creates an account and is signed in', (tester) async {
      final h = await startSignUp(tester);

      await _fill(tester, 'newbie', 'Correct-horse-1');
      await tester.tap(_submitSignUp);
      await tester.pump();
      expect(h.gateway.signUpCalls, [
        ('newbie@users.invalid', 'Correct-horse-1'),
      ]);
      expect(h.gateway.signInCalls, isEmpty);

      h.gateway.emit(userA);
      h.gateway.pendingSignUp!.complete();
      await tester.pump();
      expect(find.text('Signed in'), findsOneWidget);
      await _drainTimeouts(tester);
    });

    testWidgets('a taken username is reported without signing in', (
      tester,
    ) async {
      final h = await startSignUp(tester);
      await _fill(tester, 'alice', 'Correct-horse-1');
      await tester.tap(_submitSignUp);
      await tester.pump();

      h.gateway.pendingSignUp!.completeError(
        const AuthApiException(
          'User already registered',
          statusCode: '422',
          code: 'user_already_exists',
        ),
      );
      await tester.pump();

      expect(
        find.text('That username is taken. Choose another, or sign in.'),
        findsOneWidget,
      );
      expect(h.controller.session, isNull);
    });

    testWidgets('confirmation-required projects get clear guidance', (
      tester,
    ) async {
      final h = await startSignUp(tester);
      await _fill(tester, 'newbie', 'Correct-horse-1');
      await tester.tap(_submitSignUp);
      await tester.pump();

      h.gateway.pendingSignUp!.completeError(const ConfirmationRequired());
      await tester.pump();

      expect(
        find.text(
          'Account created, but it must be confirmed before signing in.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('mode cannot change while a request is running', (
      tester,
    ) async {
      final h = await startSignUp(tester);
      await _fill(tester, 'newbie', 'Correct-horse-1');
      await tester.tap(_submitSignUp);
      await tester.pump();

      await tester.tap(find.text('Sign in').first, warnIfMissed: false);
      await tester.pump();
      expect(find.widgetWithText(AppBar, 'Create account'), findsOneWidget);

      h.gateway.pendingSignUp!.complete();
      await tester.pump();
    });
  });

  group('signed in', () {
    testWidgets('a restored session goes straight to the account', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      expect(find.text('Signed in'), findsOneWidget);
      expect(h.api.requests, hasLength(1));
      await _drainTimeouts(tester);
    });

    testWidgets('API outage keeps the session and offers retry', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.api.respond(0, 503, '{"error":{"code":"auth_unavailable"}}');
      await tester.pump();

      expect(
        find.text('The API could not be reached. You are still signed in.'),
        findsOneWidget,
      );
      expect(h.controller.session, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      h.api.respondUser(1, userA);
      await tester.pump();

      expect(find.text('User ID: ${userA.userId}'), findsOneWidget);
    });

    testWidgets('401 refreshes once and retries with the new token', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.api.respond(0, 401);
      await tester.pump();
      expect(h.gateway.refreshCalls, 1);

      const refreshed = AuthSession(
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'alice@users.invalid',
        accessToken: 'token-a2',
      );
      h.gateway.emit(refreshed);
      h.gateway.pendingRefresh!.complete(refreshed);
      await tester.pump();

      expect(h.api.tokenOf(1), 'token-a2');
      h.api.respondUser(1, userA);
      await tester.pump();
      expect(find.text('User ID: ${userA.userId}'), findsOneWidget);
    });

    testWidgets('a second 401 asks to sign in again without looping', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.api.respond(0, 401);
      await tester.pump();
      h.gateway.pendingRefresh!.complete(userA);
      await tester.pump();
      h.api.respond(1, 401);
      await tester.pump();

      expect(
        find.text('Your session has expired. Please sign in again.'),
        findsOneWidget,
      );
      expect(h.gateway.refreshCalls, 1);
      expect(h.api.requests, hasLength(2));
    });

    testWidgets('failed refresh asks to sign in again', (tester) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.api.respond(0, 401);
      await tester.pump();
      h.gateway.pendingRefresh!.completeError(AuthRetryableFetchException());
      await tester.pump();

      expect(
        find.text('Your session has expired. Please sign in again.'),
        findsOneWidget,
      );
      expect(h.api.requests, hasLength(1));
    });

    testWidgets('identity that differs from the session is not shown', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.api.respondUser(0, userB);
      await tester.pump();

      expect(find.textContaining(userB.userId), findsNothing);
      expect(
        find.text('The API returned an unexpected response.'),
        findsOneWidget,
      );
    });

    testWidgets('sign-out clears private UI before the server answers', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);
      h.api.respondUser(0, userA);
      await tester.pump();

      await tester.tap(_signOut);
      await tester.pump();

      expect(h.gateway.signOutCalls, 1);
      expect(find.text('Signed in'), findsNothing);
      expect(find.textContaining(userA.userId), findsNothing);
      expect(_usernameField, findsOneWidget);

      h.gateway.pendingSignOut!.complete();
      await tester.pump();
      expect(find.textContaining('could not be reached'), findsNothing);
    });

    testWidgets('a failed server sign-out is reported honestly', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      await tester.tap(_signOut);
      await tester.pump();
      h.gateway.pendingSignOut!.completeError(AuthRetryableFetchException());
      await tester.pump();

      expect(_usernameField, findsOneWidget);
      expect(
        find.text(
          'You are signed out on this device, but the server could not be '
          'reached to end the session.',
        ),
        findsOneWidget,
      );
      await _drainTimeouts(tester);
    });

    testWidgets('a delayed response for user A never shows for user B', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);
      expect(h.api.tokenOf(0), 'token-a');

      // A signs out and B signs in while A's request is still in flight.
      await tester.tap(_signOut);
      await tester.pump();
      h.gateway.pendingSignOut!.complete();
      h.gateway.emit(userB);
      await tester.pump();
      expect(h.api.tokenOf(1), 'token-b');

      h.api.respondUser(0, userA);
      await tester.pump();
      expect(find.textContaining(userA.userId), findsNothing);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('Checking your identity with the API…'), findsOneWidget);

      h.api.respondUser(1, userB);
      await tester.pump();
      expect(find.text('User ID: ${userB.userId}'), findsOneWidget);
    });

    testWidgets('a refresh that lands after an account switch is ignored', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);
      h.api.respond(0, 401);
      await tester.pump();

      h.gateway.emit(userB);
      await tester.pump();
      h.gateway.pendingRefresh!.complete(userA);
      await tester.pump();

      // Only B's own request was made after the switch.
      expect(h.api.requests.map((r) => r.headers['Authorization']), [
        'Bearer token-a',
        'Bearer token-b',
      ]);
      await _drainTimeouts(tester);
    });

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('account page fits ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final h = _Harness(userA);
        await h.pump(tester);
        h.api.respondUser(0, userA);
        await tester.pump();

        expect(tester.takeException(), isNull);
        final button = tester.getRect(_signOut);
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(size.width));
      });
    }
  });
}
