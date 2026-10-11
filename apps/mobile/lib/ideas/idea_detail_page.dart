import 'package:flutter/material.dart';

import 'category_style.dart';
import 'failure_text.dart';
import 'idea.dart';
import 'idea_form_page.dart';
import 'ideas_client.dart';
import 'ideas_repository.dart';

/// One idea with everything saved for it, including its exact original text.
class IdeaDetailPage extends StatefulWidget {
  const IdeaDetailPage({
    super.key,
    required this.repository,
    required this.ideaId,
    required this.initialTitle,
    required this.onChanged,
    required this.onDeleted,
  });

  final IdeasRepository repository;
  final String ideaId;
  final String initialTitle;

  /// Reports the latest version so the collection stays in step.
  final void Function(Idea idea) onChanged;

  /// Reports that the idea is gone (deleted here or elsewhere).
  final void Function(String id) onDeleted;

  @override
  State<IdeaDetailPage> createState() => _IdeaDetailPageState();
}

class _IdeaDetailPageState extends State<IdeaDetailPage> {
  Idea? _idea;
  bool _loading = true;
  bool _gone = false;
  bool _busy = false;
  String? _loadError;
  String? _message;
  String? _action;
  VoidCallback? _onAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _show(String? message, {String? action, VoidCallback? onAction}) {
    _message = message;
    _action = action;
    _onAction = onAction;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _show(null);
    });
    try {
      final idea = await widget.repository.get(widget.ideaId);
      if (!mounted) return;
      setState(() {
        _idea = idea;
        _loading = false;
      });
      widget.onChanged(idea);
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted) return;
      _handleGone(error);
      setState(() {
        _loading = false;
        if (!_gone) _loadError = describeIdeasFailure(error);
      });
    }
  }

  /// A 404 means the idea is no longer accessible: treat it as removed.
  bool _handleGone(Object error) {
    if (error case IdeasException(kind: IdeasFailureKind.notFound)) {
      _gone = true;
      widget.onDeleted(widget.ideaId);
      return true;
    }
    return false;
  }

  void _handleDeleteFailure(Object error) {
    if (_handleGone(error)) return;
    _show(describeIdeasFailure(error), action: 'Retry', onAction: _delete);
  }

  Future<void> _edit() async {
    final idea = _idea;
    if (idea == null || _busy) return;
    final updated = await Navigator.of(context).push<Idea>(
      MaterialPageRoute(
        builder: (_) =>
            IdeaFormPage.edit(repository: widget.repository, existing: idea),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _idea = updated;
      _show(null);
    });
    widget.onChanged(updated);
  }

  Future<void> _confirmDelete() async {
    if (_idea == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      // Inside the signed-in navigator, so signing out removes it too.
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete this idea?'),
        content: const Text(
          'The idea and its original text will be removed. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _delete();
  }

  Future<void> _delete() async {
    final idea = _idea;
    if (idea == null || _busy) return;
    setState(() {
      _busy = true;
      _show(null);
    });
    try {
      await widget.repository.delete(idea.id);
      if (!mounted) return;
      widget.onDeleted(idea.id);
      Navigator.of(context).pop();
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Retrying is safe: if the first attempt worked, the retry gets 404.
        _handleDeleteFailure(error);
      });
      if (_gone) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final idea = _idea;
    final ready = idea != null && !_gone;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          idea?.title ?? widget.initialTitle,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (ready) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : _edit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _confirmDelete,
            ),
          ],
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: SafeArea(child: _body(context, idea)),
    );
  }

  Widget _body(BuildContext context, Idea? idea) {
    Widget centered(List<Widget> children) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );

    if (_gone) {
      return centered([
        const Text('This idea no longer exists.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to your ideas'),
        ),
      ]);
    }
    if (_loading && idea == null) {
      return centered(const [CircularProgressIndicator()]);
    }
    if (idea == null) {
      return centered([
        Text(_loadError ?? 'This idea could not be loaded.'),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ]);
    }

    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final fields = idea.fields;
    final category = ideaCategories[fields.category];
    String when(DateTime time) =>
        localizations.formatMediumDate(time.toLocal());

    Widget section(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    final sources = idea.sources ?? const <IdeaSource>[];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_message!),
                        if (_action != null) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _onAction,
                            child: Text(_action!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                CategoryAvatar(category: fields.category, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        fields.title,
                        style: theme.textTheme.headlineSmall,
                      ),
                      Text(
                        [
                          category ?? 'Uncategorised',
                          relativeDay(idea.createdAt),
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: CategoryStyle.of(fields.category).color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (fields.location != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(fields.location!)),
                ],
              ),
            ],
            if (fields.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in fields.tags) Chip(label: Text('#$tag')),
                ],
              ),
            ],
            if (fields.description != null)
              section('Description', fields.description!),
            if (fields.notes != null) section('Notes', fields.notes!),
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Original text', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          source.originalText,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(
              idea.updatedAt.isAfter(idea.createdAt)
                  ? 'Saved ${when(idea.createdAt)} · edited ${when(idea.updatedAt)}'
                  : 'Saved ${when(idea.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
