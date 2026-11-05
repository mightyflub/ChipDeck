// Playlists: the main playlist, favourites and the user's own playlists,
// one at a time, picked from the panel header. Searchable; collections can
// be reordered.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../player/player_controller.dart';
import 'list_actions.dart';
import 'theme.dart';

class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({
    super.key,
    required this.controller,
    required this.onAddFiles,
    required this.onAddFolder,
    this.onPlayed,
  });

  final PlayerController controller;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback? onPlayed;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  PlayerController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shows another view (the browser, a folder or a list), with a fresh
  /// search.
  void _open(String view) {
    setState(() {
      _search.clear();
      _query = '';
    });
    c.showList(view);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _say(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );

  /// The folder shown in the browser (null: the top level).
  String? get _browsedFolder => folderOfView(c.shownList);

  Future<void> _newPlaylist({String? folder, bool open = true}) async {
    final name = await askName(
      context,
      title: 'New playlist',
      initial: c.collections.uniqueName('New playlist'),
      confirm: 'Create',
    );
    if (name == null) return;
    final id = c.createPlaylist(name, const [], folder);
    if (open) _open(id);
  }

  Future<void> _newFolder(String? parent) async {
    final name = await askName(
      context,
      title: 'New folder',
      initial: 'New folder',
      confirm: 'Create',
    );
    if (name != null) c.createFolder(name, parent: parent);
  }

  /// Actions on a playlist from the browser (or from its own header).
  Future<void> _playlistAction(String id, String v) async {
    final name = c.listName(id);
    switch (v) {
      case 'play':
        if (id == mainListId) {
          if (c.playlist.isNotEmpty) c.playIndex(0);
        } else if ((c.collections.pathsOf(id) ?? const []).isNotEmpty) {
          c.playList(id, 0);
        } else {
          _say('"$name" is empty.');
          return;
        }
        widget.onPlayed?.call();
      case 'toPlaylist':
        final n = c.addListToPlaylist(id);
        _say(
          n == 0
              ? 'Those tunes are already in Playing Now.'
              : 'Added $n tunes to Playing Now.',
        );
      case 'rename':
        final n = await askName(
          context,
          title: 'Rename playlist',
          initial: name,
          confirm: 'Rename',
        );
        if (n != null) c.renamePlaylist(id, n);
      case 'move':
        final to = await pickFolder(
          context,
          c,
          title: 'Move "$name" to',
          current: c.collections.byId(id)?.folder,
        );
        if (to != null) {
          c.movePlaylist(id, to.isEmpty ? null : to);
          final where = to.isEmpty
              ? 'the top level'
              : c.collections.folderLabel(to);
          _say('Moved "$name" to $where.');
        }
      case 'delete':
        if (await confirmAction(
          context,
          title: 'Delete "$name"?',
          message: 'The playlist goes; the tunes stay where they are.',
          confirm: 'Delete',
        )) {
          c.deletePlaylist(id);
        }
    }
  }

  Future<void> _folderAction(String id, String v) async {
    final f = c.collections.folderById(id);
    if (f == null) return;
    switch (v) {
      case 'rename':
        final n = await askName(
          context,
          title: 'Rename folder',
          initial: f.name,
          confirm: 'Rename',
        );
        if (n != null) c.renameFolder(id, n);
      case 'move':
        final to = await pickFolder(
          context,
          c,
          title: 'Move "${f.name}" to',
          current: f.parent,
          moving: id,
        );
        if (to != null) c.moveFolder(id, to.isEmpty ? null : to);
      case 'delete':
        final n = c.collections.playlistCountUnder(id);
        if (await confirmAction(
          context,
          title: 'Delete folder "${f.name}"?',
          message: n == 0
              ? 'The folder is empty.'
              : 'Its playlists and folders are kept: they move up a level.',
          confirm: 'Delete',
        )) {
          c.deleteFolder(id);
        }
    }
  }

  Future<void> _action(String v) async {
    final id = c.shownList;
    final name = c.listName(id);
    final messenger = ScaffoldMessenger.of(context);
    void say(String s) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
      );
    switch (v) {
      case 'files':
        widget.onAddFiles();
      case 'folder':
        widget.onAddFolder();
      case 'saveAs':
        final n = await askName(
          context,
          title: 'Save Playing Now as a playlist',
          initial: c.collections.uniqueName('My playlist'),
          confirm: 'Save',
        );
        if (n == null) return;
        final newId = c.savePlaylistAs(n);
        say('Saved ${c.playlist.length} tunes as "${c.listName(newId)}".');
      case 'toPlaylist':
        final n = c.addListToPlaylist(id);
        say(
          n == 0
              ? 'Those tunes are already in Playing Now.'
              : 'Added $n tunes to Playing Now.',
        );
      case 'rename' || 'move' || 'delete':
        await _playlistAction(id, v);
      case 'clear':
        if (id == mainListId) {
          c.clearPlaylist();
        } else if (await confirmAction(
          context,
          title: id == favouritesId ? 'Clear favourites?' : 'Empty "$name"?',
          message: 'This takes every tune out of the list.',
          confirm: 'Clear',
        )) {
          c.clearList(id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Its own semantics container, like the desktop Now playing: Flutter's
    // Windows accessibility bridge crashed on reparented nodes (NOTES.md,
    // 0.9.0-test.79), and switching lists swaps the whole subtree.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    return ColoredBox(
      color: Palette.panel,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final id = c.shownList;
          if (!c.isTuneList(id)) return _browser();
          final isMain = id == mainListId;
          final entries = isMain ? c.playlist : c.collectionEntries(id);
          final q = _query.toLowerCase();
          final indices = <int>[
            for (var i = 0; i < entries.length; i++)
              if (q.isEmpty ||
                  entries[i].title.toLowerCase().contains(q) ||
                  entries[i].author.toLowerCase().contains(q) ||
                  entries[i].fileName.toLowerCase().contains(q))
                i,
          ];
          return LayoutBuilder(
            builder: (context, box) {
              // Short screens: list picker, search and actions share a row.
              final compact = box.maxHeight < 480;
              // Wide enough for one line per tune.
              final dense = box.maxWidth >= 560;
              final showSearch = entries.isNotEmpty;
              return Column(
                children: [
                  Padding(
                    padding: compact
                        ? const EdgeInsets.fromLTRB(4, 6, 4, 6)
                        : const EdgeInsets.fromLTRB(8, 10, 8, 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to the playlists',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => _open(c.parentView(id)),
                        ),
                        if (compact && showSearch) ...[
                          Flexible(
                            flex: 2,
                            child: _ListTitle(
                              controller: c,
                              id: id,
                              compact: true,
                              count: entries.length,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(flex: 3, child: _searchField()),
                        ] else
                          Expanded(
                            child: _ListTitle(
                              controller: c,
                              id: id,
                              compact: compact,
                              count: entries.length,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'List actions',
                          icon: const Icon(Icons.more_vert),
                          onSelected: _action,
                          itemBuilder: (_) => _actionItems(id, entries),
                        ),
                      ],
                    ),
                  ),
                  if (showSearch && !compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _searchField(),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? (isMain
                              ? _EmptyState(
                                  onAddFiles: widget.onAddFiles,
                                  onAddFolder: widget.onAddFolder,
                                )
                              : _EmptyCollection(
                                  favourites: id == favouritesId,
                                ))
                        : Scrollbar(
                            controller: _scroll,
                            child: isMain
                                ? _mainList(indices, dense)
                                : _collectionList(id, entries, indices, dense),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// The list of playlists: Playlist and Favourites at the top, then the
  /// folders and playlists of the folder being browsed. The search box
  /// finds playlists and folders by name anywhere.
  Widget _browser() {
    final col = c.collections;
    final folderId = _browsedFolder;
    final folder = col.folderById(folderId);
    final q = _query.trim().toLowerCase();
    final rows = <Widget>[];
    if (q.isNotEmpty) {
      for (final f in col.folders) {
        if (f.name.toLowerCase().contains(q)) rows.add(_folderRow(f, true));
      }
      final hits =
          col.playlists.where((p) => p.name.toLowerCase().contains(q)).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      for (final p in hits) {
        rows.add(_playlistRow(p.id, true));
      }
    } else {
      if (folder == null) {
        rows
          ..add(_playlistRow(mainListId, false))
          ..add(_playlistRow(favouritesId, false));
        if (col.folders.isNotEmpty || col.playlists.isNotEmpty) {
          rows.add(const Divider(height: 1, indent: 16, endIndent: 16));
        }
      }
      for (final f in col.foldersIn(folderId)) {
        rows.add(_folderRow(f, false));
      }
      for (final p in col.playlistsIn(folderId)) {
        rows.add(_playlistRow(p.id, false));
      }
    }
    final empty = rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              q.isNotEmpty ? 'No playlists or folders match.' : 'This folder is empty. Make a playlist here with +, or move one in from its menu.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textMuted),
            ),
          )
        : null;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 480;
        final t = Theme.of(context).textTheme;
        final path = col.folderLabel(folder?.parent);
        final title = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder?.name ?? 'Playlists',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact ? t.titleSmall : t.titleMedium,
            ),
            if (folder != null && path.isNotEmpty && !compact)
              Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Palette.textMuted, fontSize: 11),
              ),
          ],
        );
        return Column(
          children: [
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(4, 6, 4, 6)
                  : const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Row(
                children: [
                  if (folder != null)
                    IconButton(
                      tooltip: 'Up a level',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _open(c.parentView(c.shownList)),
                    )
                  else
                    const SizedBox(width: 8),
                  if (compact) ...[
                    Flexible(flex: 2, child: title),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: _searchField(hint: 'Search playlists'),
                    ),
                  ] else
                    Expanded(child: title),
                  IconButton(
                    tooltip: 'New playlist',
                    icon: const Icon(Icons.add),
                    onPressed: () => _newPlaylist(folder: folderId),
                  ),
                  IconButton(
                    tooltip: 'New folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => _newFolder(folderId),
                  ),
                  if (folder != null)
                    PopupMenuButton<String>(
                      tooltip: 'Folder actions',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) => _folderAction(folder.id, v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename folder…'),
                        ),
                        PopupMenuItem(
                          value: 'move',
                          child: Text('Move folder to…'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete folder…'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _searchField(hint: 'Search playlists'),
              ),
            const Divider(height: 1),
            Expanded(
              child:
                  empty ??
                  Scrollbar(
                    controller: _scroll,
                    child: ListView(controller: _scroll, children: rows),
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _playlistRow(String id, bool showWhere) {
    final col = c.collections;
    final count = id == mainListId
        ? c.playlist.length
        : (col.pathsOf(id)?.length ?? 0);
    final user = col.byId(id) != null;
    final where = showWhere ? col.folderLabel(col.byId(id)?.folder) : '';
    final playing = c.playingList == id;
    return _BrowserRow(
      icon: playing ? Icons.graphic_eq : _listIcon(id),
      iconColor: id == favouritesId
          ? Palette.star
          : (playing ? Palette.accent : null),
      title: c.listName(id),
      subtitle: [
        count == 1 ? '1 tune' : '$count tunes',
        if (where.isNotEmpty) where,
      ].join(' · '),
      onTap: () => _open(id),
      trailing: [
        IconButton(
          tooltip: 'Play',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: count == 0 ? null : () => _playlistAction(id, 'play'),
        ),
        if (user)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) => _playlistAction(id, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'toPlaylist',
                child: Text('Add all to Playing Now'),
              ),
              PopupMenuItem(value: 'rename', child: Text('Rename…')),
              PopupMenuItem(value: 'move', child: Text('Move to folder…')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist…')),
            ],
          )
        else
          const SizedBox(width: 40),
      ],
    );
  }

  Widget _folderRow(PlaylistFolder f, bool showWhere) {
    final col = c.collections;
    final n = col.playlistCountUnder(f.id);
    final where = showWhere ? col.folderLabel(f.parent) : '';
    return _BrowserRow(
      icon: Icons.folder_outlined,
      iconColor: Palette.warm,
      title: f.name,
      subtitle: [
        n == 1 ? '1 playlist' : '$n playlists',
        if (where.isNotEmpty) where,
      ].join(' · '),
      onTap: () => _open(folderView(f.id)),
      trailing: [
        const Icon(Icons.chevron_right, color: Palette.textMuted),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (v) => _folderAction(f.id, v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename…')),
            PopupMenuItem(value: 'move', child: Text('Move to…')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('Delete folder…')),
          ],
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _actionItems(
    String id,
    List<PlaylistEntry> entries,
  ) {
    PopupMenuItem<String> item(String v, String text, {bool enabled = true}) =>
        PopupMenuItem(value: v, enabled: enabled, child: Text(text));
    final has = entries.isNotEmpty;
    if (id == mainListId) {
      return [
        item('files', 'Add files…'),
        item('folder', 'Add folder…'),
        item('saveAs', 'Save as a new playlist…', enabled: has),
        const PopupMenuDivider(),
        item('clear', 'Clear Playing Now', enabled: has),
      ];
    }
    return [
      item('toPlaylist', 'Add all to Playing Now', enabled: has),
      if (id != favouritesId) ...[
        item('rename', 'Rename…'),
        item('move', 'Move to folder…'),
      ],
      const PopupMenuDivider(),
      if (id == favouritesId)
        item('clear', 'Clear favourites…', enabled: has)
      else ...[
        item('clear', 'Empty this playlist…', enabled: has),
        item('delete', 'Delete playlist…'),
      ],
    ];
  }

  Widget _mainList(List<int> indices, bool dense) {
    return ListView.builder(
      controller: _scroll,
      itemCount: indices.length,
      itemExtent: dense ? 40 : 56,
      itemBuilder: (context, row) {
        final i = indices[row];
        final e = c.playlist[i];
        return _PlaylistRow(
          controller: c,
          listId: mainListId,
          dense: dense,
          index: i,
          entry: e,
          isCurrent: i == c.currentIndex,
          isPlaying: i == c.currentIndex && c.playing,
          onTap: () {
            c.playIndex(i);
            widget.onPlayed?.call();
          },
          onRemove: () => c.removeAt(i),
          removeOnLongPress: true,
        );
      },
    );
  }

  Widget _collectionList(
    String id,
    List<PlaylistEntry> entries,
    List<int> indices,
    bool dense,
  ) {
    // Reordering only makes sense on the whole list, not search results.
    final canMove = _query.isEmpty && entries.length > 1;
    final playingHere = c.playingList == id;
    final currentPath = c.current?.path;
    return ReorderableListView.builder(
      scrollController: _scroll,
      buildDefaultDragHandles: false,
      itemCount: indices.length,
      itemExtent: dense ? 40 : 56,
      onReorderItem: (from, to) {
        if (canMove) c.moveInList(id, from, to);
      },
      itemBuilder: (context, row) {
        final i = indices[row];
        final e = entries[i];
        final isCurrent = playingHere && e.path == currentPath;
        return _PlaylistRow(
          key: ValueKey(e.path),
          controller: c,
          listId: id,
          dense: dense,
          index: i,
          entry: e,
          isCurrent: isCurrent,
          isPlaying: isCurrent && c.playing,
          onTap: () {
            c.playList(id, i);
            widget.onPlayed?.call();
          },
          onRemove: () => c.removeFromList(id, i),
          dragIndex: canMove ? row : null,
        );
      },
    );
  }

  Widget _searchField({String hint = 'Search title, author or file'}) {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              ),
        filled: true,
        fillColor: Palette.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

IconData _listIcon(String id) => switch (id) {
  mainListId => Icons.queue_music,
  favouritesId => Icons.star_rounded,
  _ => Icons.playlist_play,
};

/// Header naming the list shown, with its folder and tune count.
class _ListTitle extends StatelessWidget {
  const _ListTitle({
    required this.controller,
    required this.id,
    required this.compact,
    required this.count,
  });

  final PlayerController controller;
  final String id;
  final bool compact;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final where = controller.collections.folderLabel(
      controller.collections.byId(id)?.folder,
    );
    return Row(
      children: [
        Icon(
          _listIcon(id),
          size: 20,
          color: id == favouritesId ? Palette.star : Palette.accent,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.listName(id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: compact ? t.titleSmall : t.titleMedium,
              ),
              if (where.isNotEmpty && !compact)
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Palette.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        if (count > 0) ...[const SizedBox(width: 6), _Badge(text: '$count')],
      ],
    );
  }
}

/// A playlist or folder in the browser.
class _BrowserRow extends StatelessWidget {
  const _BrowserRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.trailing,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? Palette.textMuted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatefulWidget {
  const _PlaylistRow({
    super.key,
    required this.controller,
    required this.listId,
    required this.index,
    required this.entry,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onRemove,
    this.dense = false,
    this.removeOnLongPress = false,
    this.dragIndex,
  });

  final PlayerController controller;

  /// The list this row is in.
  final String listId;

  /// One line: number, title, author, subtunes (wide lists).
  final bool dense;
  final int index;
  final PlaylistEntry entry;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// Long press removes the tune (the main playlist, as before 0.11).
  final bool removeOnLongPress;

  /// Row position for dragging, or null when the list can't be reordered.
  final int? dragIndex;

  @override
  State<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends State<_PlaylistRow> {
  bool _hover = false;

  /// True while the row menu is open. Keeps the menu button in the tree
  /// when the pointer leaves the row: a PopupMenuButton that is no longer
  /// mounted drops the choice (0.11.0-test.102: "add to another playlist"
  /// did nothing on Windows).
  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (mounted && _menuOpen != open) setState(() => _menuOpen = open);
  }

  /// Touch screens have no hover: the row menu is always shown.
  static final bool _touch = Platform.isAndroid || Platform.isIOS;

  String get _removeLabel => switch (widget.listId) {
    mainListId => 'Remove from Playing Now',
    favouritesId => 'Remove from favourites',
    _ => 'Remove from this playlist',
  };

  Future<void> _menu(String v) async {
    final c = widget.controller;
    final e = widget.entry;
    switch (v) {
      case 'fav':
        c.toggleFavourite(e.path, e.info);
      case 'remove':
        widget.onRemove();
      default:
        await addToListPicked(context, c, v, [(e.path, e.info)]);
    }
  }

  Widget _rowMenu() {
    final c = widget.controller;
    final fav = c.isFavourite(widget.entry.path);
    return PopupMenuButton<String>(
      // Keyed so it keeps its state while the hover tools around it come
      // and go.
      key: const ValueKey('rowMenu'),
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 18, color: Palette.textMuted),
      padding: EdgeInsets.zero,
      onOpened: () => _setMenuOpen(true),
      onCanceled: () => _setMenuOpen(false),
      onSelected: (v) {
        _setMenuOpen(false);
        _menu(v);
      },
      itemBuilder: (_) => [
        if (widget.listId != favouritesId)
          PopupMenuItem(
            value: 'fav',
            child: ListTile(
              dense: true,
              leading: Icon(
                fav ? Icons.star_rounded : Icons.star_outline_rounded,
                color: Palette.star,
              ),
              title: Text(fav ? 'Remove from favourites' : 'Add to favourites'),
            ),
          ),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.close),
            title: Text(_removeLabel),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('ADD TO', style: TextStyle(fontSize: 11)),
        ),
        ...listMenuItems(c, except: widget.listId),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final c = widget.controller;
    final subs = e.info?.subtunes ?? 0;
    final dim = e.failed ? 0.45 : 1.0;
    final titleColor = widget.isCurrent ? Palette.accent : Colors.white;
    final fav = widget.listId != favouritesId && c.isFavourite(e.path);
    final showTools = _hover || _touch || _menuOpen;
    final drag = widget.dragIndex;
    final title = Text(
      e.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: titleColor,
        fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    final sub = Text(
      e.failed
          ? 'Cannot read ${e.fileName}'
          : (e.author.isEmpty ? e.fileName : e.author),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Palette.textMuted, fontSize: 12),
    );
    Widget row = Material(
      color: widget.isCurrent
          ? Palette.accent.withValues(alpha: 0.12)
          : (_hover ? Palette.panelHigh : Colors.transparent),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.removeOnLongPress ? widget.onRemove : null,
        child: Opacity(
          opacity: dim,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: widget.isPlaying
                      ? const Icon(
                          Icons.graphic_eq,
                          size: 18,
                          color: Palette.accent,
                        )
                      : Text(
                          '${widget.index + 1}',
                          style: const TextStyle(
                            color: Palette.textMuted,
                            fontSize: 12,
                            fontFeatures: tabular,
                          ),
                        ),
                ),
                if (widget.dense) ...[
                  Expanded(flex: 5, child: title),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: sub),
                ] else
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 2), sub],
                    ),
                  ),
                if (fav && !_hover)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Palette.star,
                    ),
                  ),
                if (!_hover && subs > 1)
                  _Badge(text: '$subs', tooltip: '$subs subtunes'),
                if (_hover && widget.listId != favouritesId)
                  FavouriteButton(
                    controller: c,
                    path: e.path,
                    info: e.info,
                    size: 18,
                  ),
                if (_hover && !_touch)
                  IconButton(
                    tooltip: _removeLabel,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Palette.textMuted,
                    ),
                    onPressed: widget.onRemove,
                  ),
                if (showTools) _rowMenu() else const SizedBox(width: 8),
                if (drag != null && !_touch)
                  ReorderableDragStartListener(
                    index: drag,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: Palette.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Touch: long press and drag to reorder.
    if (drag != null && _touch) {
      row = ReorderableDelayedDragStartListener(index: drag, child: row);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: row,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.tooltip});
  final String text;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.panelHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Palette.textMuted,
          fontFeatures: tabular,
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.favourites});
  final bool favourites;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              favourites ? Icons.star_outline_rounded : Icons.playlist_play,
              size: 48,
              color: favourites ? Palette.star : Palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              favourites ? 'No favourites yet' : 'This playlist is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              favourites
                  ? 'Tap the star next to a tune in the library, a playlist or Now playing (or press F).'
                  : 'Use the add-to-playlist button next to any tune in the library, a playlist or Now playing.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFiles, required this.onAddFolder});
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 48,
              color: Palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No tunes yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Add .sid, .sndh, .ym, .mod, .xm or TFMX (mdat.*) files, or a whole folder such as your HVSC collection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.textMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAddFiles,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add files'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
