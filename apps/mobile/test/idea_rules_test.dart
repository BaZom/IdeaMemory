import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ideas/idea_rules.dart';

void main() {
  test(
    'tags are trimmed, de-duplicated ignoring case, empty pieces dropped',
    () {
      expect(parseTags(' Food, , food ,Travel,'), ['Food', 'Travel']);
      expect(parseTags('   '), isEmpty);
    },
  );

  test('lengths count characters, not UTF-16 units', () {
    final emoji = '\u{1F600}' * 3;
    expect(emoji.length, 6);
    expect(characterCount(emoji), 3);
  });
}
