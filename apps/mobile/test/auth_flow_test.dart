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
      ideas = FakeIdeasApi(answerListsEmpty: true) {
    controller = AuthController(gateway);
  }

  final FakeAuthGateway gateway;
  final FakeIdeasApi ideas;
  late final AuthController controller;

  /// Pumps the app; a restored session lands on the collection, from which
  /// the account page (the subject of these tests) is opened.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ShellApp(
        home: AuthGate(controller: controller, ideasClient: ideas.client()),
      ),
    );
    addTearDown(controller.dispose);
    if (gateway.currentSession != null) await openAccount(tester);
  }

  Future<void> openAccount(WidgetTester tester) async {
    await tester.pump();
    expect(find.text('Your ideas'), findsOneWidget);
    await tester.tap(find.byTooltip('Account'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

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
      await h.openAccount(tester);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('users.invalid'), findsNothing);
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
  });

  group('sign-up', () {
    Future<_Harness> startSignUp(WidgetTester tester) async {
      final h = _Harness();
      await h.pump(tester);
      await tester.tap(_signUpTab);
      await tester.pump();
      return h;
    }

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
      await h.openAccount(tester);
      expect(find.text('Signed in'), findsOneWidget);
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
  });

  group('signed in', () {
    testWidgets('sign-out clears private UI before the server answers', (
      tester,
    ) async {
      final h = _Harness(userA);
      await h.pump(tester);

      await tester.tap(_signOut);
      await tester.pump();

      expect(h.gateway.signOutCalls, 1);
      expect(find.text('Signed in'), findsNothing);
      expect(find.text('alice'), findsNothing);
      expect(_usernameField, findsOneWidget);

      h.gateway.pendingSignOut!.complete();
      await tester.pump();
      expect(find.textContaining('could not be reached'), findsNothing);
    });

    testWidgets('switching accounts shows only the new user', (tester) async {
      final h = _Harness(userA);
      await h.pump(tester);

      h.gateway.emit(userB);
      await tester.pump();
      await h.openAccount(tester);

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
    });

    for (final size in [const Size(320, 568)]) {
      testWidgets('account page fits ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _Harness(userA).pump(tester);

        expect(tester.takeException(), isNull);
        final button = tester.getRect(_signOut);
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(size.width));
      });
    }
  });
}
