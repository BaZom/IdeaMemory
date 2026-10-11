import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'auth_gateway.dart';

const minPasswordLength = 8;

/// A short, safe message for the user. Raw provider text is never shown.
String describeAuthError(Object error, {required bool signingUp}) {
  if (error is ConfirmationRequired) {
    return 'Account created, but it must be confirmed before signing in.';
  }
  if (error is AuthException) {
    final code = error.code;
    final status = error.statusCode;
    if (code == 'invalid_credentials' || code == 'email_not_confirmed') {
      return 'Username or password is incorrect.';
    }
    if (code == 'user_already_exists' || code == 'email_exists') {
      return 'That username is taken. Choose another, or sign in.';
    }
    if (code == 'email_address_invalid' || code == 'validation_failed') {
      return 'That username cannot be used. Try another.';
    }
    if (code == 'weak_password') {
      return 'Choose a password with at least $minPasswordLength characters.';
    }
    if (code == 'signup_disabled' || code == 'email_provider_disabled') {
      return signingUp
          ? 'New accounts cannot be created right now.'
          : 'Sign-in is not available right now.';
    }
    if (status == '429' || (code?.startsWith('over_') ?? false)) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (status == null || status.startsWith('5')) {
      return 'Could not reach the sign-in service. Check your connection and try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
