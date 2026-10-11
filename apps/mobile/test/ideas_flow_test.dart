import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/auth/auth_controller.dart';
import 'package:mobile/auth/auth_gate.dart';
import 'package:mobile/auth/auth_gateway.dart';

import 'fakes.dart';

const _emptyPage = {'items': <Object?>[], 'next_cursor': null};

class _Harness {
  _Harness([AuthSession? session = userA])
    : gateway = FakeAuthGateway(session),
      ideas = FakeIdeasApi() {
    controller = AuthController(gateway);
  }

  final FakeAuthGateway gateway;
  final FakeIdeasApi ideas;
  late final AuthController controller;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ShellApp(
        home: AuthGate(controller: controller, ideasClient: ideas.client()),
      ),
    );
    addTearDown(controller.dispose);
  }

  /// Signed in with a collection holding [items].
  Future<void> pumpWith(
    WidgetTester tester,
    List<Map<String, Object?>> items, {
    String? nextCursor,
  }) async {
    await pump(tester);
    ideas.respond(0, 200, {
      'items': [for (final i in items) Map.of(i)..remove('sources')],
      'next_cursor': nextCursor,
    });
    await tester.pump();
  }
}

Map<String, Object?> _body(_Harness h, int index) =>
    jsonDecode(h.ideas.requests[index].body) as Map<String, Object?>;

/// Lets route transitions finish (progress indicators never settle).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _openNewIdea(WidgetTester tester) async {
  await tester.tap(find.text('New idea'));
  await _settle(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pump();
}

Future<void> _openDetail(
  WidgetTester tester,
  _Harness h,
  String title,
  Map<String, Object?> full,
) async {
  await tester.tap(find.text(title));
  await _settle(tester);
  h.ideas.respond(h.ideas.count - 1, 200, full);
  await tester.pump();
}

/// Like [testWidgets], then lets unanswered requests reach their timeout so
/// no timer outlives the test.
void _testWidgets(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pump(const Duration(seconds: 16));
    });

void main() {
  group('collection', () {
    _testWidgets('signed-in users land on their collection', (tester) async {
      final h = _Harness();
      await h.pump(tester);

      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Loading your ideas…'), findsOneWidget);
      expect(h.ideas.tokenOf(0), 'token-a');
      expect(h.ideas.requests[0].url.queryParameters, {'limit': '20'});

      h.ideas.respond(0, 200, _emptyPage);
      await tester.pump();
      expect(find.text('No ideas yet'), findsOneWidget);
    });

    _testWidgets('shows entries and loads more pages', (tester) async {
      final h = _Harness();
      await h.pumpWith(tester, [
        ideaJson(
          id: 'aaaaaaaa-0000-4000-8000-000000000003',
          title: 'Newest',
          category: 'food',
        ),
        ideaJson(id: 'aaaaaaaa-0000-4000-8000-000000000002', title: 'Middle'),
      ], nextCursor: 'cursor-1');

      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Middle'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(h.ideas.requests[1].url.queryParameters['cursor'], 'cursor-1');
      h.ideas.respond(1, 200, {
        'items': [
          ideaJson(
            id: 'aaaaaaaa-0000-4000-8000-000000000001',
            title: 'Oldest',
            sources: null,
          ),
        ],
        'next_cursor': null,
      });
      await tester.pump();

      expect(find.text('Oldest'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    _testWidgets('quick add saves a title with Enter', (tester) async {
      final h = _Harness();
      await h.pumpWith(tester, []);

      await tester.enterText(
        find.widgetWithText(TextField, 'What do you want to remember?'),
        '  Ramen in Kreuzberg ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(h.ideas.requests[1].method, 'POST');
      expect(_body(h, 1)['title'], 'Ramen in Kreuzberg');
      h.ideas.respond(1, 201, ideaJson(title: 'Ramen in Kreuzberg'));
      await tester.pump();
      expect(find.text('Ramen in Kreuzberg'), findsOneWidget);
      expect(find.text('Idea saved'), findsOneWidget);
    });

    _testWidgets('category chips filter the collection', (tester) async {
      final h = _Harness();
      await h.pumpWith(tester, [ideaJson(title: 'Dune', category: 'book')]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
      await tester.pump();

      expect(h.ideas.requests[1].url.queryParameters['category'], 'food');
      h.ideas.respond(1, 200, _emptyPage);
      await tester.pump();
      expect(find.text('Dune'), findsNothing);
      expect(find.text('No food ideas yet'), findsOneWidget);
    });

    _testWidgets('deleting every loaded idea still reaches later pages', (
      tester,
    ) async {
      final h = _Harness();
      final first = ideaJson(title: 'Only loaded');
      await h.pumpWith(tester, [first], nextCursor: 'cursor-1');
      await _openDetail(tester, h, 'Only loaded', first);
      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      h.ideas.respond(2, 204);
      await _settle(tester);

      expect(find.text('No ideas yet'), findsNothing);
      expect(find.text('No ideas left'), findsNothing);
      expect(h.ideas.requests[3].url.queryParameters['cursor'], 'cursor-1');
      h.ideas.fail(3);
      await tester.pump();
      expect(find.text('More ideas could not be loaded.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pump();
      h.ideas.respond(4, 200, {
        'items': [
          ideaJson(
            id: 'aaaaaaaa-0000-4000-8000-000000000009',
            title: 'Older idea',
            sources: null,
          ),
        ],
        'next_cursor': null,
      });
      await tester.pump();
      expect(find.text('Older idea'), findsOneWidget);
    });

    _testWidgets('an expired session asks to sign in again', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      h.ideas.respond(0, 401);
      await tester.pump();
      h.gateway.pendingRefresh!.complete(null);
      await tester.pump();

      expect(
        find.text('Your session has expired. Please sign in again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sign in again'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    });
  });

  group('create', () {
    _testWidgets('a title alone is enough', (tester) async {
      final h = _Harness();
      await h.pumpWith(tester, []);
      await _openNewIdea(tester);

      await tester.enterText(_field('Title'), '  Try the ramen place ');
      await _save(tester);

      final request = h.ideas.requests[1];
      expect(request.method, 'POST');
      expect(_body(h, 1), {
        'title': 'Try the ramen place',
        'description': null,
        'notes': null,
        'location': null,
        'category': null,
        'tags': <Object?>[],
      });
      h.ideas.respond(1, 201, ideaJson(title: 'Try the ramen place'));
      await _settle(tester);

      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Try the ramen place'), findsOneWidget);
      expect(find.text('Idea saved'), findsOneWidget);
    });

    _testWidgets('a failed save keeps the draft for another try', (
      tester,
    ) async {
      final h = _Harness();
      await h.pumpWith(tester, []);
      await _openNewIdea(tester);
      await tester.enterText(_field('Title'), 'Keep me');

      await _save(tester);
      h.ideas.fail(1);
      await tester.pump();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('Keep me'), findsOneWidget);
      await _save(tester);
      h.ideas.respond(2, 201, ideaJson(title: 'Keep me'));
      await _settle(tester);
      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Keep me'), findsOneWidget);
    });

    _testWidgets('optional details and exact original text are sent', (
      tester,
    ) async {
      // Tall enough to show every field without scrolling.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = _Harness();
      await h.pumpWith(tester, []);
      await _openNewIdea(tester);
      await tester.tap(find.text('More details'));
      await tester.pump();

      await tester.enterText(_field('Title'), 'Pasta');
      await tester.enterText(_field('Description'), '  Fresh  ');
      await tester.enterText(_field('Tags'), 'Italy, italy, dinner,');
      await tester.enterText(_field('Location'), ' ');
      await tester.enterText(
        _field('Original text (optional)'),
        '  keep\n  this  ',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await _settle(tester);
      await tester.tap(find.text('Recipe').last);
      await _settle(tester);
      await _save(tester);

      expect(_body(h, 1), {
        'title': 'Pasta',
        'description': 'Fresh',
        'notes': null,
        'location': null,
        'category': 'recipe',
        'tags': ['Italy', 'dinner'],
        'original_text': '  keep\n  this  ',
      });
    });

    _testWidgets('leaving with edits asks first and saves nothing', (
      tester,
    ) async {
      final h = _Harness();
      await h.pumpWith(tester, []);
      await _openNewIdea(tester);
      await tester.enterText(_field('Title'), 'Draft');

      await tester.pageBack();
      await _settle(tester);
      expect(find.text('Discard this draft?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _settle(tester);
      expect(find.text('Draft'), findsOneWidget);

      await tester.pageBack();
      await _settle(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);
      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
      expect(h.ideas.count, 1);
    });

    _testWidgets('a 401 refreshes once and retries the save', (tester) async {
      final h = _Harness();
      await h.pumpWith(tester, []);
      await _openNewIdea(tester);
      await tester.enterText(_field('Title'), 'Refresh');
      await _save(tester);

      h.ideas.respond(1, 401);
      await tester.pump();
      const refreshed = AuthSession(
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'alice@users.invalid',
        accessToken: 'token-a2',
      );
      h.gateway.pendingRefresh!.complete(refreshed);
      await tester.pump();

      expect(h.ideas.tokenOf(2), 'token-a2');
      expect(h.ideas.requests[2].body, h.ideas.requests[1].body);
    });
  });

  group('detail and edit', () {
    final full = ideaJson(
      title: 'Ramen',
      description: 'Rich broth',
      notes: 'Go early',
      location: 'Berlin',
      category: 'food',
      tags: ['noodles', 'Japan'],
      sources: [textSource('  as  written\n\tby me ')],
    );

    _testWidgets('shows every field and the exact original text', (
      tester,
    ) async {
      final h = _Harness();
      await h.pumpWith(tester, [full]);
      await _openDetail(tester, h, 'Ramen', full);

      expect(
        h.ideas.requests[1].url.path,
        '/api/v1/ideas/aaaaaaaa-0000-4000-8000-000000000001',
      );
      for (final text in [
        'Rich broth',
        'Go early',
        'Berlin',
        'Food',
        'noodles',
        'Japan',
      ]) {
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
      final original = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == '  as  written\n\tby me ',
        ),
      );
      expect(original.data, '  as  written\n\tby me ');
    });

    _testWidgets('editing saves all fields and can clear values', (
      tester,
    ) async {
      final h = _Harness();
      await h.pumpWith(tester, [full]);
      await _openDetail(tester, h, 'Ramen', full);
      await tester.tap(find.byTooltip('Edit'));
      await _settle(tester);

      expect(find.text('Rich broth'), findsOneWidget);
      expect(find.text('noodles, Japan'), findsOneWidget);
      expect(find.text('Original text (optional)'), findsNothing);
      await tester.enterText(_field('Title'), 'Ramen bar');
      await tester.enterText(_field('Description'), '');
      await _save(tester);

      expect(h.ideas.requests[2].method, 'PATCH');
      expect(_body(h, 2), {
        'title': 'Ramen bar',
        'description': null,
        'notes': 'Go early',
        'location': 'Berlin',
        'category': 'food',
        'tags': ['noodles', 'Japan'],
      });
      h.ideas.respond(2, 200, {
        ...full,
        'title': 'Ramen bar',
        'description': null,
      });
      await _settle(tester);
      expect(find.text('Ramen bar'), findsWidgets);
      expect(find.text('Rich broth'), findsNothing);
      expect(find.text('  as  written\n\tby me '), findsOneWidget);
    });
  });

  group('delete', () {
    final full = ideaJson(title: 'Old idea', sources: [textSource('t')]);

    Future<_Harness> openIdea(WidgetTester tester) async {
      final h = _Harness();
      await h.pumpWith(tester, [full]);
      await _openDetail(tester, h, 'Old idea', full);
      return h;
    }

    _testWidgets('confirmed delete removes it from the collection', (
      tester,
    ) async {
      final h = await openIdea(tester);

      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      expect(h.ideas.requests[2].method, 'DELETE');
      expect(h.ideas.requests[2].url.queryParameters, isEmpty);
      h.ideas.respond(2, 204);
      await _settle(tester);

      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Old idea'), findsNothing);
      expect(find.text('No ideas left'), findsOneWidget);
    });

    _testWidgets('a failed delete stays visible; a retry that finds it gone '
        'counts as removed', (tester) async {
      final h = await openIdea(tester);
      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();

      h.ideas.fail(2);
      await tester.pump();
      expect(find.text('Old idea'), findsWidgets);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      expect(h.ideas.requests[3].method, 'DELETE');
      h.ideas.respondError(3, 404, 'idea_not_found');
      await _settle(tester);

      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('Old idea'), findsNothing);
    });
  });

  group('session isolation', () {
    _testWidgets('signing out discards drafts and private pages', (
      tester,
    ) async {
      final h = _Harness();
      await h.pumpWith(tester, [ideaJson(title: 'A secret idea')]);
      await _openNewIdea(tester);
      await tester.enterText(_field('Title'), 'A unsaved draft');

      final signedOut = h.controller.signOut();
      await _settle(tester);
      h.gateway.pendingSignOut!.complete();
      await signedOut;

      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
      expect(find.text('A unsaved draft'), findsNothing);
      expect(find.text('A secret idea'), findsNothing);

      h.gateway.emit(userB);
      await _settle(tester);
      expect(find.text('Your ideas'), findsOneWidget);
      expect(find.text('A unsaved draft'), findsNothing);
      expect(h.ideas.tokenOf(1), 'token-b');
    });

    _testWidgets('a delayed response for A never shows for B', (tester) async {
      final h = _Harness();
      await h.pump(tester);

      h.gateway.emit(userB);
      await tester.pump();
      expect(h.ideas.tokenOf(1), 'token-b');

      h.ideas.respond(0, 200, {
        'items': [ideaJson(title: 'A secret idea', sources: null)],
        'next_cursor': null,
      });
      await tester.pump();
      expect(find.text('A secret idea'), findsNothing);

      h.ideas.respond(1, 200, _emptyPage);
      await tester.pump();
      expect(find.text('No ideas yet'), findsOneWidget);
    });
  });

  group('small screens', () {
    for (final size in [const Size(320, 568)]) {
      _testWidgets('pages fit ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final long = 'A very long idea title that needs to wrap ' * 4;
        final full = ideaJson(
          title: long.trim(),
          description: 'Description ' * 40,
          tags: [for (var i = 0; i < 20; i++) 'tag-$i'],
          sources: [textSource('Original ' * 100)],
        );
        final h = _Harness();
        await h.pumpWith(tester, [full]);
        expect(tester.takeException(), isNull);

        await _openDetail(tester, h, long.trim(), full);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Edit'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.showKeyboard(_field('Title'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
