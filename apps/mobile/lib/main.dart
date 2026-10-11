import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_gateway.dart';
import 'config.dart';
import 'ideas/ideas_client.dart';

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

  final controller = AuthController(SupabaseAuthGateway(supabase.client.auth));
  runApp(
    ShellApp(
      home: AuthGate(
        controller: controller,
        ideasClient: IdeasClient(
          baseUrl: config.apiBaseUrl,
          httpClient: http.Client(),
        ),
      ),
    ),
  );
}
