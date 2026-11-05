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

  void _show(String id) async {
    if (id == 'new') {
      final name = await askName(
        context,
        title: 'New playlist',
        initial: c.collections.uniqueName('New playlist'),
        confirm: 'Create',
      );
      if (name == null) return;
      id = c.createPlaylist(name);
    }
    c.showList(id);
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
          title: 'Save playlist as',
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
              ? 'Those tunes are already in the playlist.'
              : 'Added $n tunes to the playlist.',
        );
      case 'rename':
        final n = await askName(
          context,
          title: 'Rename playlist',
          initial: name,
          confirm: 'Rename',
        );
        if (n != null) c.renamePlaylist(id, n);
      case 'delete':
        if (await confirmAction(
          context,
          title: 'Delete "$name"?',
          message: 'The playlist goes; the tunes stay where they are.',
          confirm: 'Delete',
        )) {
          c.deletePlaylist(id);
        }
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
                        if (compact && showSearch) ...[
                          Flexible(
                            flex: 2,
                            child: _ListPicker(
                              controller: c,
                              onPicked: _show,
                              compact: true,
                              count: entries.length,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(flex: 3, child: _searchField()),
                        ] else
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _ListPicker(
                                controller: c,
                                onPicked: _show,
                                compact: compact,
                                count: entries.length,
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: c.shuffle ? 'Shuffle on' : 'Shuffle off',
                          isSelected: c.shuffle,
                          icon: const Icon(Icons.shuffle),
                          selectedIcon: const Icon(
                            Icons.shuffle_on_outlined,
                            color: Palette.accent,
                          ),
                          onPressed: c.toggleShuffle,
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
        item('clear', 'Clear playlist', enabled: has),
      ];
    }
    return [
      item('toPlaylist', 'Add all to Playlist', enabled: has),
      if (id != favouritesId) item('rename', 'Rename…'),
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

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search title, author or file',
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

/// Header button naming the list shown; opens the menu of lists.
class _ListPicker extends StatelessWidget {
  const _ListPicker({
    required this.controller,
    required this.onPicked,
    required this.compact,
    required this.count,
  });

  final PlayerController controller;
  final ValueChanged<String> onPicked;
  final bool compact;

  /// Tunes in the list shown.
  final int count;

  static IconData iconFor(String id) => switch (id) {
    mainListId => Icons.queue_music,
    favouritesId => Icons.star_rounded,
    _ => Icons.playlist_play,
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final id = c.shownList;
    PopupMenuItem<String> item(String value, String name, int count) =>
        PopupMenuItem(
          value: value,
          child: ListTile(
            dense: true,
            selected: value == id,
            leading: Icon(
              iconFor(value),
              color: value == favouritesId ? Palette.star : null,
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              '$count',
              style: const TextStyle(
                color: Palette.textMuted,
                fontFeatures: tabular,
              ),
            ),
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'Show another list',
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      onSelected: onPicked,
      itemBuilder: (_) => [
        item(mainListId, 'Playlist', c.playlist.length),
        item(favouritesId, 'Favourites', c.collections.favourites.length),
        for (final pl in c.collections.playlists)
          item(pl.id, pl.name, pl.paths.length),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'new',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.add),
            title: Text('New playlist…'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              iconFor(id),
              size: 20,
              color: id == favouritesId ? Palette.star : Palette.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                c.listName(id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? Theme.of(context).textTheme.titleSmall
                    : Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              _Badge(text: '$count'),
            ],
            const Icon(Icons.arrow_drop_down, color: Palette.textMuted),
          ],
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

  /// Touch screens have no hover: the row menu is always shown.
  static final bool _touch = Platform.isAndroid || Platform.isIOS;

  String get _removeLabel => switch (widget.listId) {
    mainListId => 'Remove from playlist',
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
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 18, color: Palette.textMuted),
      padding: EdgeInsets.zero,
      onSelected: _menu,
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
    final showTools = _hover || _touch;
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
