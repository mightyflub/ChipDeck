// Player state for the UI: playlist, transport, settings, auto-advance.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../hvsc/stil.dart';
import '../native/chipdeck_ffi.dart';
import 'collections.dart';
import 'shuffle.dart';

export 'collections.dart'
    show
        mainListId,
        favouritesId,
        homeId,
        folderView,
        folderOfView,
        UserPlaylist,
        PlaylistFolder;

/// File extensions the core can play.
const supportedExtensions = {
  '.sid', '.psid', '.rsid', '.mus', '.prg', // C64
  '.sndh', '.snd', '.ym', // Atari ST
  '.mod', // Amiga Protracker / Soundtracker modules
  '.xm', // Fasttracker 2 modules
  // Chris Huelsbeck's TFMX (Amiga, and TFMX-ST on the Atari ST): the music
  // data file; its samples file (smpl.* / .smpl / .sam) is found next to it.
  '.mdat', '.tfx', '.tfm', '.tfmx',
  // Jochen Hippel's TFMX and Future Composer (same library as TFMX).
  '.hip', '.hipc', '.hip7', '.sog', '.fc', '.fc13', '.fc14', '.smod',
};

/// Amiga-style name prefixes ("mod.axelf", "mdat.turrican").
const supportedPrefixes = ['mod.', 'mdat.', 'hip.', 'hipc.', 'hip7.', 'fc.'];

/// Whether ChipDeck can play [path], judged by its name: a supported
/// extension, or an Amiga-style prefix ("mod.axelf", "mdat.turrican").
/// TFMX samples files (smpl.*) are not tunes on their own and are left out.
bool isSupportedFile(String path) {
  final name = p.basename(path).toLowerCase();
  for (final pre in supportedPrefixes) {
    if (name.startsWith(pre) && name.length > pre.length) return true;
  }
  return supportedExtensions.contains(p.extension(name));
}

class PlaylistEntry {
  PlaylistEntry(this.path);
  final String path;
  TuneInfo? info;
  bool failed = false;

  String get fileName => p.basename(path);
  String get title => (info?.title.isNotEmpty ?? false)
      ? info!.title
      : p.basenameWithoutExtension(path);
  String get author => info?.author ?? '';
}

// Isolate entry points are top-level so they capture nothing from the UI.
List<String> _scanFolder(String dir) {
  final out = <String>[];
  try {
    for (final f in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (f is File && isSupportedFile(f.path)) {
        out.add(f.path);
      }
    }
  } catch (_) {}
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

List<TuneInfo?> _probeFiles(List<String> paths, String? songlengths) {
  final n = ChipDeckNative.open();
  return [for (final f in paths) n.probe(f, songlengths: songlengths)];
}

enum AdvanceMode { subtunesThenNext, nextFile, repeatOne }

class PlayerController extends ChangeNotifier {
  PlayerController._(this._engine, this._prefs);

  final ChipDeckEngine? _engine;
  final SharedPreferences _prefs;

  static Future<PlayerController> create() async {
    final prefs = await SharedPreferences.getInstance();
    ChipDeckEngine? engine;
    String? error;
    try {
      engine = ChipDeckEngine.create();
      if (engine == null) error = 'No audio output device found.';
    } catch (e) {
      error = 'Could not load the ChipDeck engine: $e';
    }
    final c = PlayerController._(engine, prefs);
    c.engineError = error;
    c._restore();
    return c;
  }

  // ------------------------------------------------------------ state
  String? engineError;
  String? message; // transient error shown in a snackbar
  final List<PlaylistEntry> playlist = [];
  int? currentIndex;

  /// Tunes played straight from the library (a folder or search results).
  /// They are not added to the playlist: next/previous step through this
  /// list instead. Only one of [currentIndex] and [_queueIndex] is set.
  List<PlaylistEntry> _queue = const [];
  int? _queueIndex;

  /// Where [_queue] came from: null for the library, else the id of a
  /// collection (favourites or one of the user's playlists).
  String? _queueSource;

  /// Favourites and the user's own playlists.
  final collections = Collections();

  /// What the Playlists panel shows: [homeId] (the list of playlists), a
  /// folder ([folderView] of its id), or a list: [mainListId],
  /// [favouritesId] or a user playlist id.
  String shownList = homeId;

  /// Lists tunes were added to most recently (first = newest), offered
  /// first in the "add to" menus.
  final List<String> recentLists = [];

  /// Looks up a tune's details in the library index (set in main.dart),
  /// so favourites and playlists show titles without probing the files.
  TuneInfo? Function(String path)? lookupInfo;

  /// Entries for collection tunes, by path, so details are probed once.
  final Map<String, PlaylistEntry> _entries = {};
  final Set<String> _probed = {};
  TuneInfo? info;
  bool playing = false;
  int positionMs = 0;

  // settings
  double volume = 0.8;
  SidModel sidModel = SidModel.auto;
  String? songlengthsPath;
  int defaultLengthSec = 180; // used when Songlengths has no entry; 0 = forever
  AdvanceMode advanceMode = AdvanceMode.subtunesThenNext;
  bool shuffle = false;

  /// Visualiser shows one scope per channel (true) or the mixed output.
  bool showChannels = true;

  /// HVSC STIL.txt (tune information); BUGlist.txt is read from beside it.
  String? stilPath;
  StilDatabase? stil;

  /// Landscape layout shows the STIL info instead of the visualiser.
  bool showTuneInfo = false;

  /// STIL/BUGlist entries for the current tune (cached per file).
  TuneStil? get tuneStil {
    final s = stil, e = current;
    if (s == null || e == null) return null;
    if (_stilFor != e.path) {
      _stilFor = e.path;
      _tuneStil = s.lookup(e.path);
    }
    return _tuneStil;
  }

  String? _stilFor;
  TuneStil? _tuneStil;

  Timer? _ticker;

  /// Called after the user picks a different Songlengths file.
  VoidCallback? onSonglengthsChanged;
  String get engineVersion => _engine?.version ?? '';
  bool get hasEngine => _engine != null;

  PlaylistEntry? get current => currentIndex != null
      ? playlist[currentIndex!]
      : (_queueIndex != null ? _queue[_queueIndex!] : null);

  /// True while playing tunes from the library rather than the playlist.
  bool get playingFromLibrary => _queueIndex != null && _queueSource == null;

  /// The list the current tune is played from: [mainListId], a collection
  /// id, or null for the library (or nothing playing).
  String? get playingList => currentIndex != null
      ? mainListId
      : (_queueIndex != null ? _queueSource : null);

  /// Whether next/previous have a list to step through.
  bool get canSkip => listLength > 0;

  /// Position (1-based, 0 = none) and length of the list being played:
  /// the playlist, or the library list a tune was started from.
  int get listPosition => (currentIndex ?? _queueIndex ?? -1) + 1;
  int get listLength => _queueIndex != null ? _queue.length : playlist.length;

  int? get effectiveLengthMs {
    final l = info?.lengthMs;
    if (l != null) return l;
    return defaultLengthSec > 0 ? defaultLengthSec * 1000 : null;
  }

  bool get lengthIsKnown => info?.lengthMs != null;

  // ----------------------------------------------------------- settings
  void _restore() {
    volume = _prefs.getDouble('volume') ?? 0.8;
    sidModel = SidModel.values[(_prefs.getInt('sidModel') ?? 0).clamp(0, 2)];
    songlengthsPath = _prefs.getString('songlengths');
    defaultLengthSec = _prefs.getInt('defaultLength') ?? 180;
    advanceMode =
        AdvanceMode.values[(_prefs.getInt('advance') ?? 0).clamp(
          0,
          AdvanceMode.values.length - 1,
        )];
    shuffle = _prefs.getBool('shuffle') ?? false;
    showChannels = _prefs.getBool('channelScopes') ?? true;
    showTuneInfo = _prefs.getBool('tuneInfo') ?? false;
    stilPath = _prefs.getString('stil');
    final e = _engine;
    if (e != null) {
      e.volume = volume;
      e.sidModel = sidModel;
      if (songlengthsPath != null && !e.loadSonglengths(songlengthsPath!)) {
        songlengthsPath = null;
      }
    }
    // Older settings have Songlengths but no STIL: look beside it.
    if (stilPath == null && songlengthsPath != null) {
      stilPath = _stilBeside(songlengthsPath!);
    }
    if (stilPath != null) _loadStil(stilPath!);
    collections.load(
      favourites: _prefs.getStringList('favourites'),
      playlists: _prefs.getString('userPlaylists'),
      folders: _prefs.getString('playlistFolders'),
    );
    recentLists.addAll(
      (_prefs.getStringList('recentLists') ?? const []).where(
        (id) => collections.byId(id) != null,
      ),
    );
    // The Playlists panel always starts on the list of playlists
    // (Stephen, 2026-11-05).
    shownList = homeId;
    final saved = _prefs.getStringList('playlist') ?? const [];
    addFiles(saved.where((f) => File(f).existsSync()).toList(), persist: false);
    final lastTune = _prefs.getString('lastTune');
    final last = _prefs.getInt('lastIndex');
    if (lastTune != null && File(lastTune).existsSync()) {
      // Last tune came from the library or a collection: bring it back
      // without adding it to the playlist. From a collection, next and
      // previous carry on through it.
      final source = _prefs.getString('lastSource');
      final at = source == null
          ? -1
          : (collections.pathsOf(source)?.indexOf(lastTune) ?? -1);
      if (at >= 0) {
        _queue = collectionEntries(source!, probe: false);
        _queueIndex = at;
        _queueSource = source;
      } else {
        _queue = [PlaylistEntry(lastTune)];
        _queueIndex = 0;
      }
      _loadCurrent(autoplay: false);
    } else if (last != null && last >= 0 && last < playlist.length) {
      currentIndex = last;
      _loadCurrent(autoplay: false);
    }
  }

  void setVolume(double v) {
    volume = v;
    _engine?.volume = v;
    _prefs.setDouble('volume', v);
    notifyListeners();
  }

  void setSidModel(SidModel m) {
    sidModel = m;
    _engine?.sidModel = m;
    _prefs.setInt('sidModel', m.index);
    // Restart the current subtune so the change is audible.
    if (current != null) {
      final sub = info?.currentSubtune ?? 0;
      _loadCurrent(subtune: sub, autoplay: playing);
    }
    notifyListeners();
  }

  bool setSonglengths(String? path) {
    if (path == null) {
      songlengthsPath = null;
      _prefs.remove('songlengths');
      notifyListeners();
      return true;
    }
    final ok = _engine?.loadSonglengths(path) ?? false;
    if (ok) {
      songlengthsPath = path;
      _prefs.setString('songlengths', path);
      info = _engine?.info;
      _probeAll(force: true);
      onSonglengthsChanged?.call();
      if (stilPath == null) {
        final st = _stilBeside(path);
        if (st != null) setStil(st);
      }
    } else {
      message = 'Could not read Songlengths file.';
    }
    notifyListeners();
    return ok;
  }

  static String? _stilBeside(String songlengths) {
    final f = File(p.join(p.dirname(songlengths), 'STIL.txt'));
    return f.existsSync() ? f.path : null;
  }

  /// Sets the STIL.txt file (null clears it). Loads in the background.
  Future<bool> setStil(String? path) async {
    if (path == null) {
      stilPath = null;
      stil = null;
      _stilFor = null;
      _prefs.remove('stil');
      notifyListeners();
      return true;
    }
    if (path == stilPath && stil != null) return true;
    final previous = stilPath;
    stilPath = path; // set now so a second auto-detect does not load it again
    final ok = await _loadStil(path);
    if (ok) {
      _prefs.setString('stil', path);
    } else {
      stilPath = previous;
      message = 'Could not read STIL file.';
    }
    notifyListeners();
    return ok;
  }

  Future<bool> _loadStil(String path) async {
    final db = await StilDatabase.load(path);
    if (db == null) return false;
    stil = db;
    _stilFor = null;
    notifyListeners();
    return true;
  }

  void toggleTuneInfo() {
    showTuneInfo = !showTuneInfo;
    _prefs.setBool('tuneInfo', showTuneInfo);
    notifyListeners();
  }

  void setDefaultLength(int seconds) {
    defaultLengthSec = seconds;
    _prefs.setInt('defaultLength', seconds);
    notifyListeners();
  }

  void setAdvanceMode(AdvanceMode m) {
    advanceMode = m;
    _prefs.setInt('advance', m.index);
    notifyListeners();
  }

  /// Random order for next/previous while [shuffle] is on.
  final _order = ShuffleOrder();

  void toggleShuffle() {
    shuffle = !shuffle;
    _order.reset();
    _prefs.setBool('shuffle', shuffle);
    notifyListeners();
  }

  // ----------------------------------------------------------- playlist
  void addFiles(List<String> paths, {bool persist = true}) {
    final existing = playlist.map((e) => e.path).toSet();
    final added = <PlaylistEntry>[];
    for (final f in paths) {
      if (existing.contains(f)) continue;
      if (!isSupportedFile(f)) continue;
      final e = PlaylistEntry(f);
      playlist.add(e);
      added.add(e);
      existing.add(f);
    }
    if (persist) _savePlaylist();
    notifyListeners();
    _probe(added);
  }

  /// Adds tunes whose metadata is already known (from the library index).
  /// [replace] clears the playlist first; [play] starts the first added tune.
  void addKnown(
    List<(String, TuneInfo)> items, {
    bool replace = false,
    bool play = false,
  }) {
    if (replace) {
      stop();
      playlist.clear();
      currentIndex = null;
      _clearQueue();
      info = null;
    }
    final existing = {
      for (var i = 0; i < playlist.length; i++) playlist[i].path: i,
    };
    int? first;
    for (final (path, tuneInfo) in items) {
      final at = existing[path];
      if (at != null) {
        first ??= at;
        continue;
      }
      final e = PlaylistEntry(path)..info = tuneInfo;
      playlist.add(e);
      existing[path] = playlist.length - 1;
      first ??= playlist.length - 1;
    }
    _savePlaylist();
    notifyListeners();
    if (play && first != null) playIndex(first);
  }

  /// Adds every supported file below [dir] (recursively, sorted by path).
  Future<int> addFolder(String dir) async {
    final files = await Isolate.run(() => _scanFolder(dir));
    final before = playlist.length;
    addFiles(files);
    return playlist.length - before;
  }

  void removeAt(int index) {
    if (index < 0 || index >= playlist.length) return;
    playlist.removeAt(index);
    if (currentIndex != null) {
      if (index == currentIndex) {
        stop();
        currentIndex = null;
        info = null;
      } else if (index < currentIndex!) {
        currentIndex = currentIndex! - 1;
      }
    }
    _savePlaylist();
    notifyListeners();
  }

  void clearPlaylist() {
    playlist.clear();
    if (currentIndex != null) {
      // Leave a tune playing from the library alone.
      stop();
      currentIndex = null;
      info = null;
    }
    _savePlaylist();
    notifyListeners();
  }

  void _savePlaylist() {
    _prefs.setStringList('playlist', playlist.map((e) => e.path).toList());
    if (currentIndex != null) _prefs.setInt('lastIndex', currentIndex!);
  }

  void _clearQueue() {
    _queue = const [];
    _queueIndex = null;
    _queueSource = null;
  }

  // -------------------------------------------- favourites and playlists
  /// The name shown for a list id.
  String listName(String id) => switch (id) {
    mainListId => 'Playing Now',
    favouritesId => 'Favourites',
    _ => collections.byId(id)?.name ?? 'Playlist',
  };

  /// Whether [id] is a list of tunes (not the browser or a folder).
  bool isTuneList(String id) =>
      id == mainListId || collections.pathsOf(id) != null;

  bool _validView(String id) {
    if (id == homeId || isTuneList(id)) return true;
    final f = folderOfView(id);
    return f != null && collections.folderById(f) != null;
  }

  /// Shows the browser ([homeId]), a folder ([folderView]) or a list.
  void showList(String id) {
    if (!_validView(id)) id = homeId;
    if (shownList == id) return;
    shownList = id;
    notifyListeners();
  }

  /// Where "back" goes from [view]: a list or folder's folder, else home.
  String parentView(String view) {
    final String? folder;
    if (folderOfView(view) case final f?) {
      folder = collections.folderById(f)?.parent;
    } else {
      folder = collections.byId(view)?.folder;
    }
    return folder == null ? homeId : folderView(folder);
  }

  void _touchRecent(String id) {
    if (collections.byId(id) == null) return;
    recentLists
      ..remove(id)
      ..insert(0, id);
    if (recentLists.length > 5) recentLists.removeRange(5, recentLists.length);
    _prefs.setStringList('recentLists', recentLists);
  }

  String createFolder(String name, {String? parent}) {
    final f = collections.createFolder(name, parent: parent);
    _saveCollections();
    notifyListeners();
    return f.id;
  }

  void renameFolder(String id, String name) {
    if (collections.renameFolder(id, name)) {
      _saveCollections();
      notifyListeners();
    }
  }

  /// Deletes a folder; what was in it moves up a level.
  void deleteFolder(String id) {
    final up = parentView(folderView(id));
    if (!collections.deleteFolder(id)) return;
    if (shownList == folderView(id)) showList(up);
    _saveCollections();
    notifyListeners();
  }

  void movePlaylist(String id, String? folder) {
    if (collections.movePlaylist(id, folder)) {
      _saveCollections();
      notifyListeners();
    }
  }

  bool moveFolder(String id, String? parent) {
    final ok = collections.moveFolder(id, parent);
    if (ok) {
      _saveCollections();
      notifyListeners();
    }
    return ok;
  }

  /// Entries (with details where known) for a collection's tunes. Tunes
  /// whose details are unknown are probed in the background.
  List<PlaylistEntry> collectionEntries(String id, {bool probe = true}) {
    final paths = collections.pathsOf(id) ?? const <String>[];
    final out = [
      for (final f in paths)
        _entries.putIfAbsent(
          f,
          () => PlaylistEntry(f)..info = lookupInfo?.call(f),
        ),
    ];
    if (probe) {
      // Each tune is probed at most once (_probed), even if it fails.
      final unknown = [
        for (final e in out)
          if (e.info == null && _probed.add(e.path)) e,
      ];
      if (unknown.isNotEmpty) _probe(unknown);
    }
    return out;
  }

  /// Remembers known details for tunes going into a collection.
  void _seed(Iterable<(String, TuneInfo?)> items) {
    for (final (path, info) in items) {
      final e = _entries.putIfAbsent(path, () => PlaylistEntry(path));
      e.info ??= info;
    }
  }

  /// Keeps next/previous in step after the collection being played from
  /// changes. If the playing tune was taken out, the old order is kept.
  void _syncQueue(String id) {
    final at = _queueIndex;
    if (_queueSource != id || at == null) return;
    final path = _queue[at].path;
    final entries = collectionEntries(id, probe: false);
    final now = entries.indexWhere((e) => e.path == path);
    if (now < 0) return;
    _queue = entries;
    _queueIndex = now;
  }

  void _saveCollections() {
    _prefs.setStringList('favourites', collections.favouritesToPrefs());
    _prefs.setString('userPlaylists', collections.playlistsToPrefs());
    _prefs.setString('playlistFolders', collections.foldersToPrefs());
  }

  bool isFavourite(String path) => collections.isFavourite(path);

  /// Stars or unstars a tune ([path], or the current tune). Returns the new
  /// state.
  bool toggleFavourite([String? path, TuneInfo? info]) {
    final e = current;
    path ??= e?.path;
    if (path == null) return false;
    _seed([(path, info ?? (path == e?.path ? e?.info : null))]);
    final on = collections.toggleFavourite(path);
    _syncQueue(favouritesId);
    _saveCollections();
    notifyListeners();
    return on;
  }

  /// Adds tunes to a list: the main playlist, favourites or a user
  /// playlist. Returns how many were new to it.
  int addToList(String id, List<(String, TuneInfo?)> items) {
    if (id == mainListId) {
      final before = playlist.length;
      final known = [
        for (final (path, info) in items)
          if (info != null) (path, info),
      ];
      if (known.length == items.length) {
        addKnown(known);
      } else {
        addFiles([for (final (path, _) in items) path]);
      }
      return playlist.length - before;
    }
    _seed(items);
    _touchRecent(id);
    final n = collections.addTo(id, [for (final (path, _) in items) path]);
    _syncQueue(id);
    _saveCollections();
    notifyListeners();
    return n;
  }

  /// Makes a new playlist (optionally with tunes) and returns its id.
  String createPlaylist(
    String name, [
    List<(String, TuneInfo?)> items = const [],
    String? folder,
  ]) {
    _seed(items);
    final pl = collections.create(
      name,
      paths: [for (final (path, _) in items) path],
      folder: folder,
    );
    _touchRecent(pl.id);
    _saveCollections();
    notifyListeners();
    return pl.id;
  }

  /// Saves the main playlist as a new named playlist.
  String savePlaylistAs(String name) =>
      createPlaylist(name, [for (final e in playlist) (e.path, e.info)]);

  void renamePlaylist(String id, String name) {
    if (collections.rename(id, name)) {
      _saveCollections();
      notifyListeners();
    }
  }

  void deletePlaylist(String id) {
    final up = parentView(id);
    if (!collections.delete(id)) return;
    if (shownList == id) showList(up);
    if (recentLists.remove(id)) {
      _prefs.setStringList('recentLists', recentLists);
    }
    if (_queueSource == id) _queueSource = null; // keeps playing its copy
    _saveCollections();
    notifyListeners();
  }

  void removeFromList(String id, int index) {
    if (id == mainListId) return removeAt(index);
    if (collections.removeAt(id, index)) {
      _syncQueue(id);
      _saveCollections();
      notifyListeners();
    }
  }

  void moveInList(String id, int oldIndex, int newIndex) {
    if (collections.move(id, oldIndex, newIndex)) {
      _syncQueue(id);
      _saveCollections();
      notifyListeners();
    }
  }

  void clearList(String id) {
    if (id == mainListId) return clearPlaylist();
    collections.clear(id);
    _saveCollections();
    notifyListeners();
  }

  /// Adds every tune of a collection to the main playlist.
  int addListToPlaylist(String id) => addToList(mainListId, [
    for (final e in collectionEntries(id, probe: false)) (e.path, e.info),
  ]);

  /// Plays a collection from [index] without touching the main playlist;
  /// next and previous step through the collection.
  void playList(String id, int index) {
    if (id == mainListId) return playIndex(index);
    final entries = collectionEntries(id);
    if (index < 0 || index >= entries.length) return;
    _queue = entries;
    _queueSource = id;
    currentIndex = null;
    _playQueue(index);
  }

  // Probe metadata in a background isolate, in batches, so the UI stays smooth.
  Future<void> _probe(List<PlaylistEntry> entries) async {
    const batch = 200;
    final songs = songlengthsPath;
    for (var i = 0; i < entries.length; i += batch) {
      final chunk = entries.sublist(i, (i + batch).clamp(0, entries.length));
      final paths = chunk.map((e) => e.path).toList();
      final results = await Isolate.run(() => _probeFiles(paths, songs));
      for (var j = 0; j < chunk.length; j++) {
        chunk[j].info = results[j];
        chunk[j].failed = results[j] == null;
      }
      notifyListeners();
    }
  }

  void _probeAll({bool force = false}) =>
      _probe(force ? playlist : playlist.where((e) => e.info == null).toList());

  // ---------------------------------------------------------- transport
  void playIndex(int index, {int subtune = 0}) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    _clearQueue();
    _prefs.setInt('lastIndex', index);
    _prefs.remove('lastTune');
    _loadCurrent(subtune: subtune, autoplay: true);
  }

  /// Plays tunes from the library without adding them to the playlist.
  /// [items] is the list the tune was picked from (a folder or search
  /// results), so next/previous carry on through it; [start] is the tune
  /// to play first.
  void playFromLibrary(List<(String, TuneInfo)> items, {int start = 0}) {
    if (items.isEmpty) return;
    _queue = [
      for (final (path, tuneInfo) in items)
        PlaylistEntry(path)..info = tuneInfo,
    ];
    _queueSource = null;
    currentIndex = null;
    _playQueue(start.clamp(0, _queue.length - 1));
  }

  void _playQueue(int index) {
    _queueIndex = index;
    _prefs.setString('lastTune', _queue[index].path);
    if (_queueSource != null) {
      _prefs.setString('lastSource', _queueSource!);
    } else {
      _prefs.remove('lastSource');
    }
    _loadCurrent(autoplay: true);
  }

  void _loadCurrent({int subtune = 0, required bool autoplay}) {
    final e = _engine;
    final entry = current;
    if (e == null || entry == null) return;
    e.playing = false;
    if (!e.load(entry.path, subtune: subtune)) {
      entry.failed = true;
      message = 'Cannot play ${entry.fileName}: ${e.lastError}';
      playing = false;
      info = null;
      notifyListeners();
      return;
    }
    info = e.info;
    entry.info ??= info;
    positionMs = 0;
    playing = autoplay;
    e.playing = autoplay;
    _ensureTicker();
    notifyListeners();
  }

  void togglePlay() {
    if (current == null) {
      if (playlist.isNotEmpty) playIndex(0);
      return;
    }
    if (info == null) {
      _loadCurrent(autoplay: true);
      return;
    }
    playing = !playing;
    _engine?.playing = playing;
    _ensureTicker();
    notifyListeners();
  }

  void stop() {
    playing = false;
    _engine?.playing = false;
    if (current != null && info != null) {
      _engine?.selectSubtune(info!.currentSubtune);
      positionMs = 0;
    }
    notifyListeners();
  }

  void selectSubtune(int n) {
    final i = info;
    if (i == null || n < 1 || n > i.subtunes) return;
    if (_engine?.selectSubtune(n) ?? false) {
      info = _engine!.info;
      positionMs = 0;
      notifyListeners();
    }
  }

  void nextSubtune() {
    final i = info;
    if (i != null && i.currentSubtune < i.subtunes) {
      selectSubtune(i.currentSubtune + 1);
    }
  }

  void previousSubtune() {
    final i = info;
    if (i != null && i.currentSubtune > 1) selectSubtune(i.currentSubtune - 1);
  }

  void nextTrack() {
    final fromLibrary = _queueIndex != null;
    final length = fromLibrary ? _queue.length : playlist.length;
    final at = fromLibrary ? _queueIndex : currentIndex;
    final go = fromLibrary ? _playQueue : playIndex;
    if (length == 0) return;
    if (shuffle && length > 1) {
      // Every tune once in a random order, then stop (as at the end of
      // the list in order).
      final n = _order.next(fromLibrary ? _queue : playlist, length, at);
      if (n == null) {
        stop();
      } else {
        go(n);
      }
      return;
    }
    final next = (at ?? -1) + 1;
    if (next < length) {
      go(next);
    } else {
      stop();
    }
  }

  void previousTrack() {
    if (positionMs > 3000 && info != null) {
      selectSubtune(info!.currentSubtune); // restart
      return;
    }
    if (shuffle) {
      // Back through the tunes played in random order.
      final fromLibrary = _queueIndex != null;
      final n = _order.previous(
        fromLibrary ? _queue : playlist,
        fromLibrary ? _queue.length : playlist.length,
        fromLibrary ? _queueIndex : currentIndex,
      );
      if (n != null) {
        fromLibrary ? _playQueue(n) : playIndex(n);
        return;
      }
    }
    if (_queueIndex != null) {
      if (_queueIndex! > 0) _playQueue(_queueIndex! - 1);
      return;
    }
    final prev = (currentIndex ?? 0) - 1;
    if (prev >= 0) playIndex(prev);
  }

  // ------------------------------------------------------- visual data
  Int16List scope(int frames) => _engine?.scope(frames) ?? Int16List(0);
  Uint8List? sidRegisters(int chip) => _engine?.sidRegisters(chip);
  List<String> get channelNames => _engine?.channelNames ?? const [];
  List<Int16List> channelScopes(int frames) =>
      _engine?.channelScopes(frames) ?? const [];

  void toggleChannelScopes() {
    showChannels = !showChannels;
    _prefs.setBool('channelScopes', showChannels);
    notifyListeners();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
  }

  void _tick() {
    final e = _engine;
    if (e == null || !playing || info == null) return;
    positionMs = e.positionMs;
    final len = effectiveLengthMs;
    if (len != null && positionMs >= len) {
      _songEnded();
    }
    notifyListeners();
  }

  void _songEnded() {
    final i = info!;
    switch (advanceMode) {
      case AdvanceMode.repeatOne:
        selectSubtune(i.currentSubtune);
      case AdvanceMode.subtunesThenNext:
        if (i.currentSubtune < i.subtunes) {
          selectSubtune(i.currentSubtune + 1);
        } else {
          nextTrack();
        }
      case AdvanceMode.nextFile:
        nextTrack();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _engine?.dispose();
    super.dispose();
  }
}
