import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../auth/auth_controller.dart';
import '../ideas/collection_page.dart';
import '../ideas/ideas_client.dart';
import '../ideas/ideas_repository.dart';

/// Everything shown while signed in, with its own navigator, dialogs and
/// snack bars. The auth gate creates one per identity, so signing out or
/// switching accounts disposes every page, draft and pending request of the
/// previous session at once.
class SignedInShell extends StatefulWidget {
  const SignedInShell({
    super.key,
    required this.controller,
    required this.ideasClient,
  });

  final AuthController controller;
  final IdeasClient ideasClient;

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _repository = IdeasRepository(
    controller: widget.controller,
    client: widget.ideasClient,
  );

  void _openAccount(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: NavigatorPopHandler<Object?>(
      // Browser/system back pops this navigator's pages first.
      onPopWithResult: (_) => _navigator.currentState?.maybePop(),
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => CollectionPage(
            repository: _repository,
            controller: widget.controller,
            onOpenAccount: _openAccount,
          ),
        ),
      ),
    ),
  );
}
