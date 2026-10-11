/// Quick checks while typing. The API is the authority: it trims text, checks
/// every limit and answers with a field error if anything is still wrong.
library;

const titleMax = 200;
const longTextMax = 10000;
const locationMax = 300;
const originalTextMax = 20000;
const tagMax = 50;
const tagsMax = 20;

/// Lengths count characters as the server does (code points, not UTF-16).
int characterCount(String value) => value.runes.length;

/// Tags typed as a comma-separated list: trimmed, empty pieces dropped,
/// duplicates (ignoring case) removed, keeping the first spelling.
List<String> parseTags(String input) {
  final tags = <String>[];
  final seen = <String>{};
  for (final piece in input.split(',')) {
    final tag = piece.trim();
    if (tag.isNotEmpty && seen.add(tag.toLowerCase())) tags.add(tag);
  }
  return tags;
}
