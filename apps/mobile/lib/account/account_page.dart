import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';

/// The signed-in username and sign-out.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = controller.session?.username;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Signed in', style: theme.textTheme.headlineSmall),
                  if (username != null) ...[
                    const SizedBox(height: 4),
                    Text(username, style: theme.textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 32),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => OutlinedButton.icon(
                      onPressed: controller.isSigningOut
                          ? null
                          : controller.signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
