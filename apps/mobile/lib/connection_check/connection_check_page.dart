import 'package:flutter/material.dart';

import 'health_client.dart';

enum _CheckStatus { loading, connected, failed }

/// Checks API connectivity once on open; retries only when the user asks.
class ConnectionCheckPage extends StatefulWidget {
  const ConnectionCheckPage({super.key, required this.healthClient});

  final HealthClient healthClient;

  @override
  State<ConnectionCheckPage> createState() => _ConnectionCheckPageState();
}

class _ConnectionCheckPageState extends State<ConnectionCheckPage> {
  _CheckStatus _status = _CheckStatus.loading;
  String? _failureMessage;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  void _retry() {
    if (_inFlight) return;
    setState(() {
      _status = _CheckStatus.loading;
      _failureMessage = null;
    });
    _runCheck();
  }

  Future<void> _runCheck() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await widget.healthClient.check();
      if (!mounted) return;
      setState(() => _status = _CheckStatus.connected);
    } on HealthCheckException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CheckStatus.failed;
        _failureMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _CheckStatus.failed;
        _failureMessage = 'Something went wrong while checking the API.';
      });
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connection check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: _StatusSummary(
                      status: _status,
                      failureMessage: _failureMessage,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'API: ${widget.healthClient.baseUrl}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (_status == _CheckStatus.failed) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _inFlight ? null : _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.status, required this.failureMessage});

  final _CheckStatus status;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (Widget indicator, String title, String? detail) = switch (status) {
      _CheckStatus.loading => (
        const SizedBox.square(
          dimension: 48,
          child: CircularProgressIndicator(),
        ),
        'Checking connection…',
        null,
      ),
      _CheckStatus.connected => (
        Icon(Icons.check_circle, size: 48, color: colors.primary),
        'Connected',
        'The API is reachable.',
      ),
      _CheckStatus.failed => (
        Icon(Icons.error, size: 48, color: colors.error),
        'Connection failed',
        failureMessage,
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: indicator),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
