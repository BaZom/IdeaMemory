import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'category_style.dart';
import 'failure_text.dart';
import 'idea.dart';
import 'idea_detail_page.dart';
import 'idea_form_page.dart';
import 'idea_rules.dart';
import 'ideas_repository.dart';

enum _LoadStatus { loading, ready, failed, sessionExpired }

/// The signed-in home: quick add, category filter and the user's ideas,
/// newest first.
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.repository,
    required this.controller,
    required this.onOpenAccount,
  });

  final IdeasRepository repository;
  final AuthController controller;
  final void Function(BuildContext context) onOpenAccount;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _quickAdd = TextEditingController();
  bool _quickSaving = false;
  String? _category;
  _LoadStatus _status = _LoadStatus.loading;
  List<Idea> _items = const [];
  String? _nextCursor;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _deletedLast = false;
  // Identifies the newest load; older responses are dropped.
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final loadId = ++_loadId;
    setState(() {
      _status = _LoadStatus.loading;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.repository.list(category: _category);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _items = page.items;
        _nextCursor = page.nextCursor;
        _status = _LoadStatus.ready;
        _deletedLast = false;
      });
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted || loadId != _loadId) return;
      setState(
        () => _status = error is SessionExpired
            ? _LoadStatus.sessionExpired
            : _LoadStatus.failed,
      );
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final loadId = _loadId;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.repository.list(
        cursor: cursor,
        category: _category,
      );
      if (!mounted || loadId != _loadId) return;
      final known = {for (final idea in _items) idea.id};
      setState(() {
        _items = [
          ..._items,
          ...page.items.where((idea) => !known.contains(idea.id)),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _loadingMore = false;
        if (error is SessionExpired) {
          _status = _LoadStatus.sessionExpired;
        } else {
          _loadMoreFailed = true;
        }
      });
    }
  }

  void _filter(String? category) {
    if (category == _category) return;
    setState(() => _category = category);
    _reload();
  }

  /// Adds [idea] at the top if it belongs to the current filter.
  void _show(Idea idea) {
    if (_category != null && idea.fields.category != _category) return;
    setState(() {
      _items = [idea, ..._items.where((i) => i.id != idea.id)];
      _status = _LoadStatus.ready;
      _deletedLast = false;
    });
  }

  void _replace(Idea idea) {
    if (!mounted) return;
    setState(() {
      _items = [for (final i in _items) i.id == idea.id ? idea : i];
    });
  }

  void _remove(String id) {
    if (!mounted) return;
    setState(() {
      final before = _items.length;
      _items = _items.where((i) => i.id != id).toList();
      _deletedLast = before > 0 && _items.isEmpty && _nextCursor == null;
    });
    // Everything loaded was deleted but more pages exist: show the next one.
    if (_items.isEmpty && _nextCursor != null) _loadMore();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveQuickIdea() async {
    final title = _quickAdd.text.trim();
    if (title.isEmpty || _quickSaving) return;
    if (characterCount(title) > titleMax) {
      _toast('Use at most $titleMax characters, or use New idea.');
      return;
    }
    setState(() => _quickSaving = true);
    try {
      final idea = await widget.repository.create(
        fields: IdeaFields(title: title),
      );
      if (!mounted) return;
      _quickAdd.clear();
      setState(() => _quickSaving = false);
      _show(idea);
      _toast('Idea saved');
    } on SessionChanged {
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _quickSaving = false);
      _toast(describeIdeasFailure(error));
    }
  }

  Future<void> _create() async {
    final idea = await Navigator.of(context).push<Idea>(
      MaterialPageRoute(
        builder: (_) => IdeaFormPage.create(repository: widget.repository),
      ),
    );
    if (idea == null || !mounted) return;
    _show(idea);
    _toast('Idea saved');
  }

  void _open(Idea idea) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => IdeaDetailPage(
          repository: widget.repository,
          ideaId: idea.id,
          initialTitle: idea.title,
          onChanged: _replace,
          onDeleted: _remove,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your ideas'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _status == _LoadStatus.loading ? null : _reload,
        ),
        IconButton(
          tooltip: 'Account',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => widget.onOpenAccount(context),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('New idea'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              _quickAddBar(),
              _categoryChips(),
              Expanded(child: _body(Theme.of(context))),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _quickAddBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      controller: _quickAdd,
      readOnly: _quickSaving,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (_) => _saveQuickIdea(),
      decoration: InputDecoration(
        hintText: 'What do you want to remember?',
        prefixIcon: const Icon(Icons.lightbulb_outline),
        filled: true,
        suffixIcon: _quickSaving
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: 'Save idea',
                icon: const Icon(Icons.send),
                onPressed: _saveQuickIdea,
              ),
      ),
    ),
  );

  Widget _categoryChips() => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: _category == null,
          onSelected: (_) => _filter(null),
        ),
        for (final entry in ideaCategories.entries) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            avatar: Icon(
              CategoryStyle.of(entry.key).icon,
              color: CategoryStyle.of(entry.key).color,
              size: 18,
            ),
            label: Text(entry.value),
            selected: _category == entry.key,
            onSelected: (selected) => _filter(selected ? entry.key : null),
          ),
        ],
      ],
    ),
  );

  Widget _body(ThemeData theme) {
    Widget centered(List<Widget> children) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            liveRegion: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );

    switch (_status) {
      case _LoadStatus.loading:
        return centered(const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your ideas…'),
        ]);
      case _LoadStatus.failed:
        return centered([
          const Text(
            'Your ideas could not be loaded. Check your connection and try '
            'again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _reload, child: const Text('Retry')),
        ]);
      case _LoadStatus.sessionExpired:
        return centered([
          const Text(
            'Your session has expired. Please sign in again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.controller.signOut,
            child: const Text('Sign in again'),
          ),
        ]);
      case _LoadStatus.ready:
        break;
    }

    if (_items.isEmpty && _nextCursor == null) {
      final category = ideaCategories[_category];
      return centered([
        const CategoryAvatar(category: null, size: 72),
        const SizedBox(height: 16),
        Text(
          category != null
              ? 'No ${category.toLowerCase()} ideas yet'
              : _deletedLast
              ? 'No ideas left'
              : 'No ideas yet',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Type something above and press Enter, for example: '
          '“Ramen place in Kreuzberg”, “Watch Dune: Part Two” or '
          '“Hike around the Schliersee”.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        // Room for the floating button below the last entry.
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => index == _items.length
            ? _footer()
            : _IdeaCard(idea: _items[index], onTap: () => _open(_items[index])),
      ),
    );
  }

  Widget _footer() {
    if (_nextCursor == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _loadingMore
            ? const CircularProgressIndicator()
            : Column(
                children: [
                  if (_loadMoreFailed) ...[
                    const Text('More ideas could not be loaded.'),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: _loadMore,
                    child: Text(_loadMoreFailed ? 'Retry' : 'Load more'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea, required this.onTap});

  final Idea idea;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = idea.fields;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final category = ideaCategories[fields.category];
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryAvatar(category: fields.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idea.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (fields.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        fields.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          [
                            ?category,
                            ?fields.location,
                            relativeDay(idea.createdAt),
                          ].join(' · '),
                          style: muted,
                        ),
                        for (final tag in fields.tags.take(4))
                          Text(
                            '#$tag',
                            style: muted?.copyWith(
                              color: CategoryStyle.of(fields.category).color,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
