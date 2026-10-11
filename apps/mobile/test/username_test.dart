import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/auth/username.dart';

void main() {
  test('normalises case and surrounding spaces', () {
    expect(normalizeUsername('  Alice.B '), 'alice.b');
  });

  for (final ok in ['abc', 'alice', 'a1_b-c.d', 'x' * 30, '123']) {
    test('accepts "$ok"', () => expect(usernameProblem(ok), isNull));
  }

  for (final bad in [
    '',
    'ab',
    'x' * 31,
    'a b',
    'a@b',
    '_abc',
    '.abc',
    'ümlaut',
    'a/b',
  ]) {
    test('rejects "$bad"', () => expect(usernameProblem(bad), isNotNull));
  }

  test('maps usernames to placeholder addresses and back', () {
    expect(usernameToEmail('alice'), 'alice@users.invalid');
    expect(usernameFromEmail('alice@users.invalid'), 'alice');
    expect(usernameFromEmail('someone@example.com'), 'someone@example.com');
    expect(usernameFromEmail(null), isNull);
  });
}
