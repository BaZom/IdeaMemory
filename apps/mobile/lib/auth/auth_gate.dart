import 'package:flutter/material.dart';

import '../home/signed_in_shell.dart';
import '../ideas/ideas_client.dart';
import 'auth_controller.dart';
import 'sign_in_page.dart';

/// Shows sign-in or the signed-in app for the current session. A new signed-in
/// shell (navigator, pages, drafts) is created for each identity, so nothing
/// from a previous user's session is carried over.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.ideasClient,
  });

  final AuthController controller;
  final IdeasClient ideasClient;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final session = controller.session;
      if (session == null) return SignInPage(controller: controller);
      return SignedInShell(
        key: ValueKey(('signed-in', session.userId, controller.generation)),
        controller: controller,
        ideasClient: ideasClient,
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
