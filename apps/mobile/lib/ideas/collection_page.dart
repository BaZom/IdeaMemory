import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'idea.dart';
import 'idea_detail_page.dart';
import 'idea_form_page.dart';
import 'ideas_repository.dart';

enum _LoadStatus { loading, ready, failed, sessionExpired }

/// The signed-in home: the user's ideas, newest first.
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

  Future<void> _reload() async {
    final loadId = ++_loadId;
    setState(() {
      _status = _LoadStatus.loading;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.repository.list();
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
      final page = await widget.repository.list(cursor: cursor);
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

  Future<void> _create() async {
    final idea = await Navigator.of(context).push<Idea>(
      MaterialPageRoute(
        builder: (_) => IdeaFormPage.create(repository: widget.repository),
      ),
    );
    if (idea == null || !mounted) return;
    setState(() {
      _items = [idea, ..._items.where((i) => i.id != idea.id)];
      _status = _LoadStatus.ready;
      _deletedLast = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Idea saved')));
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
    body: SafeArea(child: _body(Theme.of(context))),
  );

  Widget _body(ThemeData theme) {
    Widget centered(List<Widget> children) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
      return centered([
        Text(
          _deletedLast ? 'No ideas left' : 'No ideas yet',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Save something you want to remember with New idea.',
          textAlign: TextAlign.center,
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        // Room for the floating button below the last entry.
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) return _footer();
          final idea = _items[index];
          final category = ideaCategories[idea.fields.category];
          return ListTile(
            title: Text(
              idea.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: category == null ? null : Text(category),
            onTap: () => _open(idea),
          );
        },
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
