// Favourites and the user's own named playlists ("collections").
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
//
// Only paths are stored (in shared preferences); titles and authors come
// from the library index or from probing the files when a list is shown.
import 'dart:convert';

/// Id of the main playlist (the one that has always been there).
const mainListId = 'main';

/// Id of the favourites list.
const favouritesId = 'fav';

/// A named playlist the user made.
class UserPlaylist {
  UserPlaylist({required this.id, required this.name, List<String>? paths})
    : paths = paths ?? [];

  final String id;
  String name;
  final List<String> paths;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'paths': paths};

  static UserPlaylist? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], paths = j['paths'];
    if (id is! String || name is! String || paths is! List) return null;
    return UserPlaylist(
      id: id,
      name: name,
      paths: [
        for (final x in paths)
          if (x is String) x,
      ],
    );
  }
}

/// Favourites (ordered, no duplicates) and user playlists, with the plain
/// list operations. No Flutter or file access, so it is easy to test.
class Collections {
  final List<String> favourites = [];
  final Set<String> _favSet = {};
  final List<UserPlaylist> playlists = [];

  bool isFavourite(String path) => _favSet.contains(path);

  /// Adds [path] to favourites, or removes it. Returns the new state.
  bool toggleFavourite(String path) {
    if (_favSet.remove(path)) {
      favourites.remove(path);
      return false;
    }
    _favSet.add(path);
    favourites.add(path);
    return true;
  }

  UserPlaylist? byId(String id) {
    for (final pl in playlists) {
      if (pl.id == id) return pl;
    }
    return null;
  }

  /// The paths of a collection ([favouritesId] or a playlist id).
  List<String>? pathsOf(String id) =>
      id == favouritesId ? favourites : byId(id)?.paths;

  /// A name not used yet: [base], or "[base] 2", "[base] 3"...
  String uniqueName(String base) {
    final used = {for (final pl in playlists) pl.name.toLowerCase()};
    if (!used.contains(base.toLowerCase())) return base;
    for (var n = 2; ; n++) {
      final s = '$base $n';
      if (!used.contains(s.toLowerCase())) return s;
    }
  }

  UserPlaylist create(String name, {List<String> paths = const []}) {
    final pl = UserPlaylist(
      id: 'pl${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? uniqueName('New playlist') : name.trim(),
    );
    _addPaths(pl.paths, paths);
    playlists.add(pl);
    return pl;
  }

  bool rename(String id, String name) {
    final pl = byId(id);
    if (pl == null || name.trim().isEmpty) return false;
    pl.name = name.trim();
    return true;
  }

  bool delete(String id) {
    final pl = byId(id);
    if (pl == null) return false;
    playlists.remove(pl);
    return true;
  }

  /// Appends [paths] that are not in the collection yet. Returns how many
  /// were added.
  int addTo(String id, Iterable<String> paths) {
    if (id == favouritesId) {
      var n = 0;
      for (final f in paths) {
        if (_favSet.add(f)) {
          favourites.add(f);
          n++;
        }
      }
      return n;
    }
    final pl = byId(id);
    if (pl == null) return 0;
    return _addPaths(pl.paths, paths);
  }

  static int _addPaths(List<String> list, Iterable<String> paths) {
    final have = list.toSet();
    var n = 0;
    for (final f in paths) {
      if (have.add(f)) {
        list.add(f);
        n++;
      }
    }
    return n;
  }

  bool removeAt(String id, int index) {
    final list = pathsOf(id);
    if (list == null || index < 0 || index >= list.length) return false;
    final f = list.removeAt(index);
    if (id == favouritesId) _favSet.remove(f);
    return true;
  }

  void clear(String id) {
    final list = pathsOf(id);
    if (list == null) return;
    list.clear();
    if (id == favouritesId) _favSet.clear();
  }

  /// Moves the item at [oldIndex] so that it ends up at [newIndex]
  /// (ReorderableListView's onReorderItem convention).
  bool move(String id, int oldIndex, int newIndex) {
    final list = pathsOf(id);
    if (list == null || oldIndex < 0 || oldIndex >= list.length) return false;
    newIndex = newIndex.clamp(0, list.length - 1);
    if (newIndex == oldIndex) return false;
    list.insert(newIndex, list.removeAt(oldIndex));
    return true;
  }

  // ------------------------------------------------------- persistence
  List<String> favouritesToPrefs() => List.of(favourites);

  String playlistsToPrefs() =>
      jsonEncode([for (final pl in playlists) pl.toJson()]);

  void load({List<String>? favourites, String? playlists}) {
    this.favourites.clear();
    _favSet.clear();
    addTo(favouritesId, favourites ?? const []);
    this.playlists.clear();
    if (playlists != null) {
      try {
        final j = jsonDecode(playlists);
        if (j is List) {
          for (final x in j) {
            final pl = UserPlaylist.fromJson(x);
            if (pl != null && byId(pl.id) == null) this.playlists.add(pl);
          }
        }
      } catch (_) {}
    }
  }
}
