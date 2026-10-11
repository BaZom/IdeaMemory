import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'me_client.dart';

enum _IdentityStatus { loading, verified, unavailable, sessionExpired, failed }

/// Signed-in home: the identity verified by the API, and sign-out.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.controller,
    required this.meClient,
    this.onOpenDiagnostics,
  });

  final AuthController controller;
  final MeClient meClient;
  final VoidCallback? onOpenDiagnostics;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  _IdentityStatus _status = _IdentityStatus.loading;
  String? _verifiedUserId;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  void _retry() {
    if (_inFlight) return;
    setState(() => _status = _IdentityStatus.loading);
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    if (_inFlight) return;
    _inFlight = true;
    final controller = widget.controller;
    final generation = controller.generation;
    final expectedUserId = controller.session?.userId;
    // Results from a previous sign-in must never be shown for the current one.
    bool stillCurrent() => mounted && controller.generation == generation;

    void show(_IdentityStatus status, [String? userId]) {
      if (!stillCurrent()) return;
      setState(() {
        _status = status;
        _verifiedUserId = userId;
      });
    }

    try {
      var token = controller.session?.accessToken;
      if (token == null) return;
      String userId;
      try {
        userId = await widget.meClient.fetchUserId(token);
      } on MeException catch (error) {
        if (error.kind != MeFailureKind.unauthorized || !stillCurrent()) {
          rethrow;
        }
        // One SDK-mediated refresh, then a single retry.
        try {
          token = await controller.refreshAccessToken();
        } catch (_) {
          token = null;
        }
        if (!stillCurrent()) return;
        if (token == null) return show(_IdentityStatus.sessionExpired);
        userId = await widget.meClient.fetchUserId(token);
      }
      if (userId != expectedUserId) return show(_IdentityStatus.failed);
      show(_IdentityStatus.verified, userId);
    } on MeException catch (error) {
      show(switch (error.kind) {
        MeFailureKind.unauthorized => _IdentityStatus.sessionExpired,
        MeFailureKind.unavailable => _IdentityStatus.unavailable,
        MeFailureKind.invalidResponse => _IdentityStatus.failed,
      });
    } catch (_) {
      show(_IdentityStatus.failed);
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final username = controller.session?.username;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          if (widget.onOpenDiagnostics != null)
            IconButton(
              tooltip: 'Connection check',
              icon: const Icon(Icons.network_check),
              onPressed: widget.onOpenDiagnostics,
            ),
        ],
      ),
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
                  const SizedBox(height: 24),
                  Semantics(liveRegion: true, child: _identity(theme)),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: controller.isSigningOut
                        ? null
                        : controller.signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme) {
    Widget message(String text, {String? action, VoidCallback? onAction}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, style: theme.textTheme.bodyMedium),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(action)),
            ],
          ],
        );

    return switch (_status) {
      _IdentityStatus.loading => const Row(
        children: [
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Checking your identity with the API…')),
        ],
      ),
      _IdentityStatus.verified => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verified by the API', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(
            'User ID: $_verifiedUserId',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      _IdentityStatus.unavailable => message(
        'The API could not be reached. You are still signed in.',
        action: 'Retry',
        onAction: _retry,
      ),
      _IdentityStatus.sessionExpired => message(
        'Your session has expired. Please sign in again.',
        action: 'Sign in again',
        onAction: widget.controller.signOut,
      ),
      _IdentityStatus.failed => message(
        'The API returned an unexpected response.',
        action: 'Retry',
        onAction: _retry,
      ),
    };
  }
}
