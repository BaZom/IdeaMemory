/// Ideas as the API returns them, and the editable fields the app sends.
library;

/// Stable category keys and their labels. Null means uncategorised.
const Map<String, String> ideaCategories = {
  'food': 'Food',
  'activity': 'Activity',
  'travel': 'Travel',
  'film-series': 'Film / series',
  'recipe': 'Recipe',
  'product': 'Product',
  'book': 'Book',
  'place': 'Place',
  'other': 'Other',
};

/// The user-editable fields, already normalised (see idea_rules.dart).
class IdeaFields {
  const IdeaFields({
    required this.title,
    this.description,
    this.notes,
    this.location,
    this.category,
    this.tags = const [],
  });

  final String title;
  final String? description;
  final String? notes;
  final String? location;
  final String? category;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'notes': notes,
    'location': location,
    'category': category,
    'tags': tags,
  };
}

class IdeaSource {
  const IdeaSource({
    required this.id,
    required this.kind,
    required this.originalText,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String originalText;
  final DateTime createdAt;
}

class Idea {
  const Idea({
    required this.id,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
    this.sources,
  });

  final String id;
  final IdeaFields fields;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null for collection entries, which omit sources.
  final List<IdeaSource>? sources;

  String get title => fields.title;

  /// Parses an API idea. Throws [FormatException] for anything unexpected.
  factory Idea.fromJson(Object? json, {required bool withSources}) {
    if (json
        case {
          'id': final String id,
          'title': final String title,
          'description': final String? description,
          'notes': final String? notes,
          'location': final String? location,
          'category': final String? category,
          'tags': final List<Object?> tags,
          'created_at': final String createdAt,
          'updated_at': final String updatedAt,
        }
        when tags.every((tag) => tag is String)) {
      if (category != null && !ideaCategories.containsKey(category)) {
        throw const FormatException('unexpected idea values');
      }
      return Idea(
        id: id,
        fields: IdeaFields(
          title: title,
          description: description,
          notes: notes,
          location: location,
          category: category,
          tags: List.unmodifiable(tags.cast<String>()),
        ),
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
        sources: withSources ? _parseSources(json['sources']) : null,
      );
    }
    throw const FormatException('unexpected idea shape');
  }
}

List<IdeaSource> _parseSources(Object? json) {
  if (json is! List) throw const FormatException('missing sources');
  return List.unmodifiable([
    for (final source in json)
      if (source case {
        'id': final String id,
        'kind': final String kind,
        'original_text': final String originalText,
        'created_at': final String createdAt,
      })
        IdeaSource(
          id: id,
          kind: kind,
          originalText: originalText,
          createdAt: DateTime.parse(createdAt),
        )
      else
        throw const FormatException('unexpected source shape'),
  ]);
}

class IdeaPage {
  const IdeaPage({required this.items, required this.nextCursor});

  final List<Idea> items;
  final String? nextCursor;
}
