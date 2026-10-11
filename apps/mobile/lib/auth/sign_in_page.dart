import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'auth_errors.dart';
import 'username.dart';

enum AuthMode { signIn, signUp }

/// Username + password sign-in for returning users and sign-up for new ones.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  AuthMode _mode = AuthMode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  bool get _signingUp => _mode == AuthMode.signUp;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _selectMode(AuthMode mode) {
    if (_busy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = normalizeUsername(_usernameController.text);
    final password = _passwordController.text;
    final problem = username.isEmpty
        ? 'Enter a username.'
        : usernameProblem(username) ??
              (password.isEmpty
                  ? 'Enter your password.'
                  : _signingUp && password.length < minPasswordLength
                  ? 'Choose a password with at least $minPasswordLength characters.'
                  : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final signingUp = _signingUp;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (signingUp) {
        await widget.controller.signUp(username: username, password: password);
      } else {
        await widget.controller.signIn(username: username, password: password);
      }
      // On success the auth gate replaces this page.
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeAuthError(error, signingUp: signingUp));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signOutWarning = widget.controller.remoteSignOutFailed;
    final action = _signingUp ? 'Create account' : 'Sign in';
    return Scaffold(
      appBar: AppBar(title: Text(_signingUp ? 'Create account' : 'Sign in')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (signOutWarning) ...[
                      const _Notice(
                        'You are signed out on this device, but the server '
                        'could not be reached to end the session.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    SegmentedButton<AuthMode>(
                      segments: const [
                        ButtonSegment(
                          value: AuthMode.signIn,
                          label: Text('Sign in'),
                        ),
                        ButtonSegment(
                          value: AuthMode.signUp,
                          label: Text('Sign up'),
                        ),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => _selectMode(selection.single),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      enabled: !_busy,
                      autofillHints: [
                        _signingUp
                            ? AutofillHints.newUsername
                            : AutofillHints.username,
                      ],
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        helperText: _signingUp
                            ? '$minUsernameLength–$maxUsernameLength letters, '
                                  'numbers, dots, dashes or underscores'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        _signingUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _signingUp
                            ? 'At least $minPasswordLength characters'
                            : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: '$action in progress',
                              ),
                            )
                          : Text(action),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: TextStyle(color: colors.onTertiaryContainer)),
      ),
    );
  }
}
