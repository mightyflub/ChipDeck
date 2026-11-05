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

/// Menu entries for picking a list to add to; 'new' asks for a name.
List<PopupMenuEntry<String>> listMenuItems(
  PlayerController c, {
  String? except,
  bool showFavourites = false,
}) => [
  if (except != mainListId)
    const PopupMenuItem(
      value: mainListId,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.queue_music),
        title: Text('Playlist'),
      ),
    ),
  if (showFavourites && except != favouritesId)
    const PopupMenuItem(
      value: favouritesId,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.star_rounded, color: Palette.star),
        title: Text('Favourites'),
      ),
    ),
  for (final pl in c.collections.playlists)
    if (pl.id != except)
      PopupMenuItem(
        value: pl.id,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.playlist_play),
          title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
  const PopupMenuDivider(),
  const PopupMenuItem(
    value: 'new',
    child: ListTile(
      dense: true,
      leading: Icon(Icons.add),
      title: Text('New playlist…'),
    ),
  ),
];

/// Adds [items] to the list picked from [listMenuItems] and says so.
Future<void> addToListPicked(
  BuildContext context,
  PlayerController c,
  String id,
  List<(String, TuneInfo?)> items,
) async {
  if (items.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  if (id == 'new') {
    final name = await askName(
      context,
      title: 'New playlist',
      initial: c.collections.uniqueName('New playlist'),
      confirm: 'Create',
    );
    if (name == null) return;
    id = c.createPlaylist(name, items);
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
