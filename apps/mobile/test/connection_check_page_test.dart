import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/app.dart';
import 'package:mobile/connection_check/connection_check_page.dart';
import 'package:mobile/connection_check/health_client.dart';

/// Hands out one pending response per request so each test decides when and
/// how every request completes.
class _ControlledServer {
  final List<Completer<http.Response>> pending = [];

  int get requestCount => pending.length;

  HealthClient client({Duration timeout = const Duration(seconds: 8)}) =>
      HealthClient(
        baseUrl: Uri.parse('http://api.test:8000'),
        httpClient: MockClient((_) {
          final completer = Completer<http.Response>();
          pending.add(completer);
          return completer.future;
        }),
        timeout: timeout,
      );

  void respond(String body, [int status = 200]) =>
      pending.last.complete(http.Response(body, status));

  void failNetwork() =>
      pending.last.completeError(http.ClientException('connection refused'));
}

Future<void> _pumpPage(WidgetTester tester, HealthClient client) => tester
    .pumpWidget(ShellApp(home: ConnectionCheckPage(healthClient: client)));

final _retryButton = find.widgetWithText(FilledButton, 'Retry');

void main() {
  late _ControlledServer server;

  setUp(() => server = _ControlledServer());

  testWidgets('shows loading, then connected on a valid response', (
    tester,
  ) async {
    await _pumpPage(tester, server.client());

    expect(find.text('Connection check'), findsOneWidget);
    expect(find.text('Checking connection…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('API: http://api.test:8000'), findsOneWidget);
    expect(server.requestCount, 1);

    server.respond('{"status":"ok"}');
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_retryButton, findsNothing);
  });

  testWidgets('non-200 response shows failure with retry', (tester) async {
    await _pumpPage(tester, server.client());

    server.respond('{"status":"ok"}', 503);
    await tester.pump();

    expect(find.text('Connected'), findsNothing);
    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.text('The API responded with HTTP 503.'), findsOneWidget);
    expect(_retryButton, findsOneWidget);
  });

  testWidgets('malformed body shows failure', (tester) async {
    await _pumpPage(tester, server.client());

    server.respond('<html>proxy error</html>');
    await tester.pump();

    expect(find.text('Connected'), findsNothing);
    expect(
      find.text('The API returned an unexpected response.'),
      findsOneWidget,
    );
    expect(_retryButton, findsOneWidget);
  });

  testWidgets('network error shows failure', (tester) async {
    await _pumpPage(tester, server.client());

    server.failNetwork();
    await tester.pump();

    expect(find.text('The API could not be reached.'), findsOneWidget);
    expect(_retryButton, findsOneWidget);
  });

  testWidgets('timeout shows failure even if a response arrives later', (
    tester,
  ) async {
    await _pumpPage(tester, server.client(timeout: const Duration(seconds: 5)));

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Checking connection…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('The API did not respond in time.'), findsOneWidget);

    server.respond('{"status":"ok"}');
    await tester.pump();
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Connection failed'), findsOneWidget);
  });

  testWidgets('explicit retry recovers after a failure', (tester) async {
    await _pumpPage(tester, server.client());
    server.failNetwork();
    await tester.pump();

    await tester.tap(_retryButton);
    await tester.pump();

    expect(server.requestCount, 2);
    expect(find.text('Checking connection…'), findsOneWidget);
    expect(_retryButton, findsNothing);

    server.respond('{"status":"ok"}');
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('repeated taps do not start overlapping checks', (tester) async {
    await _pumpPage(tester, server.client());
    server.failNetwork();
    await tester.pump();

    // Both taps land on the same button before the frame that hides it.
    await tester.tap(_retryButton);
    await tester.tap(_retryButton);
    await tester.pump();

    expect(server.requestCount, 2);
    expect(_retryButton, findsNothing);

    server.failNetwork();
    await tester.pump();
    expect(server.requestCount, 2);
    expect(_retryButton, findsOneWidget);
  });

  testWidgets('does not retry or poll automatically', (tester) async {
    await _pumpPage(tester, server.client());
    server.failNetwork();
    await tester.pump();

    await tester.pump(const Duration(minutes: 5));

    expect(server.requestCount, 1);
    expect(find.text('Connection failed'), findsOneWidget);
  });

  testWidgets('a response after the page is removed is ignored safely', (
    tester,
  ) async {
    await _pumpPage(tester, server.client());

    await tester.pumpWidget(const SizedBox.shrink());
    server.respond('{"status":"ok"}');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a timeout after the page is removed is ignored safely', (
    tester,
  ) async {
    await _pumpPage(tester, server.client(timeout: const Duration(seconds: 1)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('failure state fits a ${size.width}x${size.height} viewport', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpPage(tester, server.client());
      server.failNetwork();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final button = tester.getRect(_retryButton);
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(size.width));
      expect(button.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    });
  }

  testWidgets('retry control is labeled for assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpPage(tester, server.client());
    server.failNetwork();
    await tester.pump();

    expect(
      tester.getSemantics(_retryButton),
      matchesSemantics(
        label: 'Retry',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
