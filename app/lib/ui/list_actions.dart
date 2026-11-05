// Shared pieces for favourites and playlists: the star button, the
// "add to playlist" menu and the name / confirm dialogs.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';

import '../native/chipdeck_ffi.dart';
import '../player/player_controller.dart';
import 'theme.dart';

/// Star toggle for one tune.
class FavouriteButton extends StatelessWidget {
  const FavouriteButton({
    super.key,
    required this.controller,
    required this.path,
    this.info,
    this.size = 20,
    this.dimWhenOff = true,
  });

  final PlayerController controller;
  final String path;
  final TuneInfo? info;
  final double size;

  /// Draw the empty star in the muted colour (lists) or normal (headers).
  final bool dimWhenOff;

  @override
  Widget build(BuildContext context) {
    final on = controller.isFavourite(path);
    return IconButton(
      tooltip: on ? 'Remove from favourites' : 'Add to favourites',
      visualDensity: VisualDensity.compact,
      onPressed: () => controller.toggleFavourite(path, info),
      icon: Icon(
        on ? Icons.star_rounded : Icons.star_outline_rounded,
        size: size,
        color: on
            ? Palette.star
            : (dimWhenOff ? Palette.textMuted : Colors.white70),
      ),
    );
  }
}

/// Menu of lists to add tunes to: the playlist, favourites, the user's own
/// playlists, and "New playlist…".
class AddToListButton extends StatelessWidget {
  const AddToListButton({
    super.key,
    required this.controller,
    required this.items,
    this.tooltip = 'Add to playlist',
    this.size = 20,
    this.except,
    this.showFavourites = false,
  });

  final PlayerController controller;

  /// The tunes to add (built when a list is picked).
  final List<(String, TuneInfo?)> Function() items;
  final String tooltip;
  final double size;

  /// A list to leave out (the one the tunes are shown in).
  final String? except;

  /// Offer Favourites too (for adding many tunes at once).
  final bool showFavourites;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      icon: Icon(Icons.playlist_add, size: size, color: Palette.textMuted),
      onSelected: (id) => addToListPicked(context, controller, id, items()),
      itemBuilder: (_) => listMenuItems(
        controller,
        except: except,
        showFavourites: showFavourites,
      ),
    );
  }
}

/// Menu entries for picking a list to add to: the Playlist, Favourites
/// (when [showFavourites]), the playlists used most recently, "Choose a
/// playlist…" (all of them, by folder) and "New playlist…".
List<PopupMenuEntry<String>> listMenuItems(
  PlayerController c, {
  String? except,
  bool showFavourites = false,
}) {
  PopupMenuItem<String> item(
    String v,
    IconData icon,
    String text, {
    Color? color,
  }) => PopupMenuItem(
    value: v,
    child: ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
  final recent = [
    for (final id in c.recentLists)
      if (id != except && c.collections.byId(id) != null) id,
  ];
  final others = c.collections.playlists.any(
    (p) => p.id != except && !recent.contains(p.id),
  );
  return [
    if (except != mainListId) item(mainListId, Icons.queue_music, 'Playlist'),
    if (showFavourites && except != favouritesId)
      item(favouritesId, Icons.star_rounded, 'Favourites', color: Palette.star),
    for (final id in recent) item(id, Icons.playlist_play, c.listName(id)),
    if (others)
      item('choose', Icons.folder_open_outlined, 'Choose a playlist…'),
    const PopupMenuDivider(),
    item('new', Icons.add, 'New playlist…'),
  ];
}

/// Adds [items] to the list picked from [listMenuItems] and says so.
Future<void> addToListPicked(
  BuildContext context,
  PlayerController c,
  String id,
  List<(String, TuneInfo?)> items,
) async {
  if (items.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  String? folder;
  if (id == 'choose') {
    final picked = await choosePlaylist(context, c);
    if (picked == null || !context.mounted) return;
    id = picked;
    if (id.startsWith('new:')) {
      folder = id.length > 4 ? id.substring(4) : null;
      id = 'new';
    }
  }
  if (id == 'new') {
    final name = await askName(
      context,
      title: 'New playlist',
      initial: c.collections.uniqueName('New playlist'),
      confirm: 'Create',
    );
    if (name == null) return;
    id = c.createPlaylist(name, items, folder);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Made "${c.listName(id)}" with ${_tunes(items.length)}.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    return;
  }
  final n = c.addToList(id, items);
  final name = c.listName(id);
  final what = id == mainListId ? 'the playlist' : '"$name"';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? (items.length == 1
                    ? 'Already in $what.'
                    : 'All of those are already in $what.')
              : 'Added ${_tunes(n)} to $what.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}

String _tunes(int n) => n == 1 ? '1 tune' : '$n tunes';

/// Asks for a playlist name. Returns null when cancelled.
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirm = 'OK',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(title: title, initial: initial, confirm: confirm),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirm,
  });
  final String title;
  final String initial;
  final String confirm;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final v = _text.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: Text(widget.confirm)),
      ],
    );
  }
}

/// Asks before something that cannot be undone. Returns true to go ahead.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Lets the user pick one of their playlists, browsing folders or
/// searching by name. Returns its id, `new:FOLDER_ID` for "New playlist
/// here" (`new:` at the top level), or null when cancelled.
Future<String?> choosePlaylist(BuildContext context, PlayerController c) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlaylistChooser(controller: c),
    );

class _PlaylistChooser extends StatefulWidget {
  const _PlaylistChooser({required this.controller});
  final PlayerController controller;

  @override
  State<_PlaylistChooser> createState() => _PlaylistChooserState();
}

class _PlaylistChooserState extends State<_PlaylistChooser> {
  String? _folder;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final col = widget.controller.collections;
    final q = _query.trim().toLowerCase();
    final folder = col.folderById(_folder);
    final rows = <Widget>[];
    if (q.isNotEmpty) {
      final hits =
          col.playlists.where((p) => p.name.toLowerCase().contains(q)).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      for (final p in hits) {
        rows.add(_playlistTile(p, col.folderLabel(p.folder)));
      }
    } else {
      if (folder != null) {
        rows.add(
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward),
            title: const Text('Up'),
            onTap: () => setState(() => _folder = folder.parent),
          ),
        );
      }
      for (final f in col.foldersIn(_folder)) {
        rows.add(
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_outlined, color: Palette.warm),
            title: Text(f.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _folder = f.id),
          ),
        );
      }
      for (final p in col.playlistsIn(_folder)) {
        rows.add(_playlistTile(p, null));
      }
    }
    return AlertDialog(
      title: Text(folder == null ? 'Add to playlist' : folder.name),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search playlists',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No playlists here.',
                        style: TextStyle(color: Palette.textMuted),
                      ),
                    )
                  : ListView(children: rows),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('New playlist here'),
          onPressed: () => Navigator.pop(context, 'new:${_folder ?? ''}'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _playlistTile(UserPlaylist p, String? where) => ListTile(
    dense: true,
    leading: const Icon(Icons.playlist_play),
    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: (where ?? '').isEmpty ? null : Text(where!),
    trailing: Text(
      '${p.paths.length}',
      style: const TextStyle(color: Palette.textMuted, fontFeatures: tabular),
    ),
    onTap: () => Navigator.pop(context, p.id),
  );
}

/// Asks which folder to move something into. Returns the folder id, ''
/// for the top level, or null when cancelled. [moving] (a folder id) and
/// the folders inside it are left out, so a folder can't go inside itself.
Future<String?> pickFolder(
  BuildContext context,
  PlayerController c, {
  required String title,
  String? current,
  String? moving,
}) {
  final col = c.collections;
  final tree = [
    for (final (f, depth) in col.folderTree())
      if (moving == null || !col.folderPath(f.id).any((x) => x.id == moving))
        (f, depth),
  ];
  Widget option(String value, String name, int depth, IconData icon) {
    final here = value == (current ?? '');
    return SimpleDialogOption(
      onPressed: here ? null : () => Navigator.pop(context, value),
      padding: EdgeInsets.fromLTRB(24.0 + depth * 20, 10, 24, 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: here ? Palette.textMuted : Palette.warm),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              here ? '$name (here now)' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: here ? Palette.textMuted : null),
            ),
          ),
        ],
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        option('', 'Top level', 0, Icons.home_outlined),
        for (final (f, depth) in tree)
          option(f.id, f.name, depth + 1, Icons.folder_outlined),
        if (tree.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              'No folders yet: make one with "New folder…" in Playlists.',
              style: TextStyle(color: Palette.textMuted),
            ),
          ),
      ],
    ),
  );
}
