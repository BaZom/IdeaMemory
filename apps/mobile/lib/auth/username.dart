/// Usernames instead of email addresses.
///
/// Supabase Auth identifies accounts by email, so each username maps to a
/// fixed placeholder address under the reserved `.invalid` domain, which can
/// never receive mail. Users never see it. Owner decision for the MVP; real
/// emails (verification, password reset) are a later task.
library;

const usernameEmailDomain = 'users.invalid';
const minUsernameLength = 3;
const maxUsernameLength = 30;

final _allowed = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

/// Lower-cases and trims, so `Alice` and `alice` are the same account.
String normalizeUsername(String raw) => raw.trim().toLowerCase();

/// A user-facing problem with [username] (already normalised), or null.
String? usernameProblem(String username) {
  if (username.length < minUsernameLength ||
      username.length > maxUsernameLength) {
    return 'Username must be $minUsernameLength–$maxUsernameLength characters.';
  }
  if (!_allowed.hasMatch(username)) {
    return 'Use letters, numbers, dots, dashes or underscores, '
        'starting with a letter or number.';
  }
  return null;
}

String usernameToEmail(String username) => '$username@$usernameEmailDomain';

/// The username behind an account's placeholder email, or the email itself
/// for accounts created another way.
String? usernameFromEmail(String? email) {
  const suffix = '@$usernameEmailDomain';
  if (email == null) return null;
  return email.endsWith(suffix)
      ? email.substring(0, email.length - suffix.length)
      : email;
}
