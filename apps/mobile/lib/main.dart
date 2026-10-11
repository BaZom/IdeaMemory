import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account/me_client.dart';
import 'app.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_gateway.dart';
import 'config.dart';
import 'connection_check/connection_check_page.dart';
import 'connection_check/health_client.dart';

Future<void> main() async {
  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on FormatException catch (error) {
    runApp(ShellApp(home: ConfigurationErrorPage(message: error.message)));
    return;
  }

  runApp(const ShellApp(home: RestoringSessionPage()));
  final Supabase supabase;
  try {
    supabase = await Supabase.initialize(
      url: config.supabaseUrl.toString(),
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // No sign-in links are used; never read tokens from the URL.
        detectSessionInUri: false,
      ),
      debug: false,
    );
  } catch (_) {
    runApp(
      const ShellApp(
        home: ConfigurationErrorPage(
          message:
              'Sign-in could not be started. Reload the page to try again.',
        ),
      ),
    );
    return;
  }

  final httpClient = http.Client();
  final healthClient = HealthClient(
    baseUrl: config.apiBaseUrl,
    httpClient: httpClient,
  );
  final controller = AuthController(SupabaseAuthGateway(supabase.client.auth));
  runApp(
    ShellApp(
      home: AuthGate(
        controller: controller,
        meClient: MeClient(baseUrl: config.apiBaseUrl, httpClient: httpClient),
        onOpenDiagnostics: (context) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConnectionCheckPage(healthClient: healthClient),
          ),
        ),
      ),
    ),
  );
}
