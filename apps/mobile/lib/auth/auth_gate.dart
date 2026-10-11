import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../account/me_client.dart';
import 'auth_controller.dart';
import 'sign_in_page.dart';

/// Shows sign-in or the signed-in app for the current session. A new page
/// state is created for each identity, so nothing from a previous user's
/// session is carried over.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.meClient,
    this.onOpenDiagnostics,
  });

  final AuthController controller;
  final MeClient meClient;
  final void Function(BuildContext context)? onOpenDiagnostics;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final openDiagnostics = onOpenDiagnostics == null
          ? null
          : () => onOpenDiagnostics!(context);
      final session = controller.session;
      if (session == null) {
        return SignInPage(
          controller: controller,
          onOpenDiagnostics: openDiagnostics,
        );
      }
      return AccountPage(
        key: ValueKey(('account', session.userId, controller.generation)),
        controller: controller,
        meClient: meClient,
        onOpenDiagnostics: openDiagnostics,
      );
    },
  );
}

/// Shown while the SDK restores a stored session on startup.
class RestoringSessionPage extends StatelessWidget {
  const RestoringSessionPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Restoring your session…'),
        ],
      ),
    ),
  );
}
