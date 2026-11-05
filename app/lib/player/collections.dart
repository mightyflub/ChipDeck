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

/// The Playlists panel's home view: the list of lists.
const homeId = 'home';

/// The view id that shows folder [id] in the Playlists panel.
String folderView(String id) => 'dir:$id';

/// The folder id of a [folderView] id, or null for other views.
String? folderOfView(String view) =>
    view.startsWith('dir:') ? view.substring(4) : null;

/// A named playlist the user made.
class UserPlaylist {
  UserPlaylist({
    required this.id,
    required this.name,
    List<String>? paths,
    this.folder,
  }) : paths = paths ?? [];

  final String id;
  String name;
  final List<String> paths;

  /// The folder it is in (a [PlaylistFolder] id), or null for the top level.
  String? folder;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'paths': paths,
    'folder': ?folder,
  };

  static UserPlaylist? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], paths = j['paths'];
    if (id is! String || name is! String || paths is! List) return null;
    final folder = j['folder'];
    return UserPlaylist(
      id: id,
      name: name,
      folder: folder is String ? folder : null,
      paths: [
        for (final x in paths)
          if (x is String) x,
      ],
    );
  }
}

/// A folder of playlists (and of other folders).
class PlaylistFolder {
  PlaylistFolder({required this.id, required this.name, this.parent});

  final String id;
  String name;

  /// The folder it is in, or null for the top level.
  String? parent;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'parent': ?parent};

  static PlaylistFolder? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], parent = j['parent'];
    if (id is! String || name is! String) return null;
    return PlaylistFolder(
      id: id,
      name: name,
      parent: parent is String ? parent : null,
    );
  }
}

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Favourites (ordered, no duplicates) and user playlists, with the plain
/// list operations. No Flutter or file access, so it is easy to test.
class Collections {
  final List<String> favourites = [];
  final Set<String> _favSet = {};
  final List<UserPlaylist> playlists = [];
  final List<PlaylistFolder> folders = [];

  static String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}';

  // ------------------------------------------------------------ folders
  PlaylistFolder? folderById(String? id) {
    if (id == null) return null;
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Folders directly inside [parent] (null: the top level), by name.
  List<PlaylistFolder> foldersIn(String? parent) =>
      folders.where((f) => f.parent == parent).toList()
        ..sort((a, b) => _byName(a.name, b.name));

  /// Playlists directly inside [folder] (null: the top level), by name.
  List<UserPlaylist> playlistsIn(String? folder) =>
      playlists.where((p) => p.folder == folder).toList()
        ..sort((a, b) => _byName(a.name, b.name));

  /// Folders from the top level down to [id] (empty for the top level).
  List<PlaylistFolder> folderPath(String? id) {
    final out = <PlaylistFolder>[];
    final seen = <String>{};
    var f = folderById(id);
    while (f != null && seen.add(f.id)) {
      out.insert(0, f);
      f = folderById(f.parent);
    }
    return out;
  }

  /// "Folder / Sub folder" for [id], or '' for the top level.
  String folderLabel(String? id) =>
      folderPath(id).map((f) => f.name).join(' / ');

  /// Playlists in [id] and all folders below it.
  int playlistCountUnder(String id) {
    final inside = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in folders) {
        if (f.parent != null && inside.contains(f.parent) && inside.add(f.id)) {
          grew = true;
        }
      }
    }
    return playlists.where((p) => inside.contains(p.folder)).length;
  }

  /// Every folder in tree order, with its depth (for pickers).
  List<(PlaylistFolder, int)> folderTree() {
    final out = <(PlaylistFolder, int)>[];
    void walk(String? parent, int depth) {
      for (final f in foldersIn(parent)) {
        out.add((f, depth));
        walk(f.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  PlaylistFolder createFolder(String name, {String? parent}) {
    final used = {
      for (final f in foldersIn(folderById(parent)?.id)) f.name.toLowerCase(),
    };
    var n = name.trim().isEmpty ? 'New folder' : name.trim();
    if (used.contains(n.toLowerCase())) {
      final base = n;
      for (var i = 2; used.contains(n.toLowerCase()); i++) {
        n = '$base $i';
      }
    }
    final f = PlaylistFolder(
      id: _newId('fd'),
      name: n,
      parent: folderById(parent)?.id,
    );
    folders.add(f);
    return f;
  }

  bool renameFolder(String id, String name) {
    final f = folderById(id);
    if (f == null || name.trim().isEmpty) return false;
    f.name = name.trim();
    return true;
  }

  /// Deletes a folder. Its playlists and folders move up to its parent, so
  /// nothing the user made is lost.
  bool deleteFolder(String id) {
    final f = folderById(id);
    if (f == null) return false;
    for (final c in folders) {
      if (c.parent == id) c.parent = f.parent;
    }
    for (final p in playlists) {
      if (p.folder == id) p.folder = f.parent;
    }
    folders.remove(f);
    return true;
  }

  /// Moves a playlist into [folder] (null: the top level).
  bool movePlaylist(String id, String? folder) {
    final p = byId(id);
    if (p == null || (folder != null && folderById(folder) == null)) {
      return false;
    }
    p.folder = folder;
    return true;
  }

  /// Moves a folder into [parent] (null: the top level). Refuses to move a
  /// folder into itself or into one of its own folders.
  bool moveFolder(String id, String? parent) {
    final f = folderById(id);
    if (f == null || (parent != null && folderById(parent) == null)) {
      return false;
    }
    if (folderPath(parent).any((x) => x.id == id)) return false;
    f.parent = parent;
    return true;
  }

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

  UserPlaylist create(
    String name, {
    List<String> paths = const [],
    String? folder,
  }) {
    final pl = UserPlaylist(
      id: _newId('pl'),
      name: name.trim().isEmpty ? uniqueName('New playlist') : name.trim(),
      folder: folderById(folder)?.id,
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

  String foldersToPrefs() => jsonEncode([for (final f in folders) f.toJson()]);

  void load({List<String>? favourites, String? playlists, String? folders}) {
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
    this.folders.clear();
    if (folders != null) {
      try {
        final j = jsonDecode(folders);
        if (j is List) {
          for (final x in j) {
            final f = PlaylistFolder.fromJson(x);
            if (f != null && folderById(f.id) == null) this.folders.add(f);
          }
        }
      } catch (_) {}
    }
    // Repair links to folders that no longer exist, and folder loops.
    for (final f in this.folders) {
      if (folderById(f.parent) == null) f.parent = null;
    }
    for (final f in this.folders) {
      final seen = <String>{f.id};
      var p = folderById(f.parent);
      while (p != null) {
        if (!seen.add(p.id)) {
          f.parent = null;
          break;
        }
        p = folderById(p.parent);
      }
    }
    for (final p in this.playlists) {
      if (folderById(p.folder) == null) p.folder = null;
    }
  }
}
