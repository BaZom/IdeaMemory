import 'package:flutter/material.dart';

import 'failure_text.dart';
import 'idea.dart';
import 'idea_rules.dart';
import 'ideas_repository.dart';

/// Review and save a new idea, or edit an existing one. Nothing is stored
/// until Save; the draft lives only in this page and survives failed saves.
class IdeaFormPage extends StatefulWidget {
  const IdeaFormPage.create({super.key, required this.repository})
    : existing = null;

  const IdeaFormPage.edit({
    super.key,
    required this.repository,
    required Idea this.existing,
  });

  final IdeasRepository repository;
  final Idea? existing;

  @override
  State<IdeaFormPage> createState() => _IdeaFormPageState();
}

class _IdeaFormPageState extends State<IdeaFormPage> {
  late final _title = TextEditingController(text: _initial?.title);
  late final _description = TextEditingController(text: _initial?.description);
  late final _notes = TextEditingController(text: _initial?.notes);
  late final _location = TextEditingController(text: _initial?.location);
  late final _tags = TextEditingController(text: _initial?.tags.join(', '));
  final _originalText = TextEditingController();
  late String? _category = _initial?.category;
  late bool _showDetails = switch (_initial) {
    null => false,
    final f =>
      f.description != null ||
          f.notes != null ||
          f.location != null ||
          f.category != null ||
          f.tags.isNotEmpty,
  };

  late final List<TextEditingController> _controllers = [
    _title,
    _description,
    _notes,
    _location,
    _tags,
    _originalText,
  ];
  late final List<String> _initialTexts;

  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _message;

  IdeaFields? get _initial => widget.existing?.fields;
  bool get _isEdit => widget.existing != null;

  bool get _dirty =>
      _category != _initial?.category ||
      [
        for (var i = 0; i < _controllers.length; i++)
          _controllers[i].text != _initialTexts[i],
      ].any((changed) => changed);

  @override
  void initState() {
    super.initState();
    _initialTexts = [for (final c in _controllers) c.text];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Trimmed fields, or null after showing what needs fixing.
  (IdeaFields, String?)? _read() {
    final errors = <String, String>{};
    String? text(String field, TextEditingController c, int max) {
      final value = c.text.trim();
      if (characterCount(value) > max) {
        errors[field] = 'Use at most $max characters.';
      }
      return value.isEmpty ? null : value;
    }

    final title = text('title', _title, titleMax);
    if (title == null) errors['title'] = 'Enter a title.';
    final description = text('description', _description, longTextMax);
    final notes = text('notes', _notes, longTextMax);
    final location = text('location', _location, locationMax);
    final tags = parseTags(_tags.text);
    if (tags.length > tagsMax) {
      errors['tags'] = 'Use at most $tagsMax different tags.';
    } else if (tags.any((tag) => characterCount(tag) > tagMax)) {
      errors['tags'] = 'Each tag can have at most $tagMax characters.';
    }
    // Original text is kept exactly as entered.
    final original = _originalText.text.trim().isEmpty
        ? null
        : _originalText.text;
    if (original != null && characterCount(original) > originalTextMax) {
      errors['original_text'] = 'Use at most $originalTextMax characters.';
    }

    setState(() {
      _errors = errors;
      if (errors.keys.any((field) => field != 'title')) _showDetails = true;
    });
    if (errors.isNotEmpty || title == null) return null;
    return (
      IdeaFields(
        title: title,
        description: description,
        notes: notes,
        location: location,
        category: _category,
        tags: tags,
      ),
      _isEdit ? null : original,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final read = _read();
    if (read == null) return;
    final (fields, originalText) = read;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final existing = widget.existing;
      final idea = existing == null
          ? await widget.repository.create(
              fields: fields,
              originalText: originalText,
            )
          : await widget.repository.update(existing.id, fields);
      if (mounted) Navigator.of(context).pop(idea);
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = describeIdeasFailure(error);
      });
    }
  }

  Future<void> _leave() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        // Inside the signed-in navigator, so signing out removes it too.
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Discard this draft?'),
          content: const Text('Your changes have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit idea' : 'New idea'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
          bottom: _saving
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_message != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        color: theme.colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_message!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _field(_title, 'Title', 'title', autofocus: !_isEdit),
                  const SizedBox(height: 8),
                  if (!_showDetails)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showDetails = true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('More details'),
                      ),
                    )
                  else
                    ..._details(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _details() => [
    _field(_description, 'Description', 'description', multiline: true),
    const SizedBox(height: 16),
    DropdownButtonFormField<String?>(
      initialValue: _category,
      decoration: const InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final entry in ideaCategories.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _saving ? null : (value) => setState(() => _category = value),
    ),
    const SizedBox(height: 16),
    _field(_tags, 'Tags', 'tags', helper: 'Separate tags with commas'),
    const SizedBox(height: 16),
    _field(_location, 'Location', 'location'),
    const SizedBox(height: 16),
    _field(_notes, 'Notes', 'notes', multiline: true),
    if (!_isEdit) ...[
      const SizedBox(height: 16),
      _field(
        _originalText,
        'Original text (optional)',
        'original_text',
        multiline: true,
        helper: 'Kept exactly as entered, separately from the fields above.',
      ),
    ],
  ];

  Widget _field(
    TextEditingController controller,
    String label,
    String field, {
    bool multiline = false,
    bool autofocus = false,
    String? helper,
  }) => TextField(
    controller: controller,
    readOnly: _saving,
    autofocus: autofocus,
    minLines: multiline ? 3 : 1,
    maxLines: multiline ? 12 : 3,
    keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
    textInputAction: multiline ? null : TextInputAction.next,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      errorText: _errors[field],
      errorMaxLines: 2,
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) {
      if (_errors.containsKey(field)) {
        setState(() => _errors = Map.of(_errors)..remove(field));
      }
    },
  );
}
