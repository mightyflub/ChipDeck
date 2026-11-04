// Player state for the UI: playlist, transport, settings, auto-advance.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../native/chipdeck_ffi.dart';

/// File extensions the core can play.
const supportedExtensions = {
  '.sid', '.psid', '.rsid', '.mus', '.prg', // C64
  '.sndh', '.snd', '.ym', // Atari ST
};

class PlaylistEntry {
  PlaylistEntry(this.path);
  final String path;
  TuneInfo? info;
  bool failed = false;

  String get fileName => p.basename(path);
  String get title =>
      (info?.title.isNotEmpty ?? false) ? info!.title : p.basenameWithoutExtension(path);
  String get author => info?.author ?? '';
}

// Isolate entry points are top-level so they capture nothing from the UI.
List<String> _scanFolder(String dir) {
  final out = <String>[];
  try {
    for (final f in Directory(dir).listSync(recursive: true, followLinks: false)) {
      if (f is File && supportedExtensions.contains(p.extension(f.path).toLowerCase())) {
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

  Timer? _ticker;
  String get engineVersion => _engine?.version ?? '';
  bool get hasEngine => _engine != null;

  PlaylistEntry? get current =>
      currentIndex == null ? null : playlist[currentIndex!];

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
    advanceMode = AdvanceMode.values[
        (_prefs.getInt('advance') ?? 0).clamp(0, AdvanceMode.values.length - 1)];
    shuffle = _prefs.getBool('shuffle') ?? false;
    final e = _engine;
    if (e != null) {
      e.volume = volume;
      e.sidModel = sidModel;
      if (songlengthsPath != null && !e.loadSonglengths(songlengthsPath!)) {
        songlengthsPath = null;
      }
    }
    final saved = _prefs.getStringList('playlist') ?? const [];
    addFiles(saved.where((f) => File(f).existsSync()).toList(), persist: false);
    final last = _prefs.getInt('lastIndex');
    if (last != null && last >= 0 && last < playlist.length) {
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
    } else {
      message = 'Could not read Songlengths file.';
    }
    notifyListeners();
    return ok;
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

  void toggleShuffle() {
    shuffle = !shuffle;
    _prefs.setBool('shuffle', shuffle);
    notifyListeners();
  }

  // ----------------------------------------------------------- playlist
  void addFiles(List<String> paths, {bool persist = true}) {
    final existing = playlist.map((e) => e.path).toSet();
    final added = <PlaylistEntry>[];
    for (final f in paths) {
      if (existing.contains(f)) continue;
      if (!supportedExtensions.contains(p.extension(f).toLowerCase())) continue;
      final e = PlaylistEntry(f);
      playlist.add(e);
      added.add(e);
      existing.add(f);
    }
    if (persist) _savePlaylist();
    notifyListeners();
    _probe(added);
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
    stop();
    playlist.clear();
    currentIndex = null;
    info = null;
    _savePlaylist();
    notifyListeners();
  }

  void _savePlaylist() {
    _prefs.setStringList('playlist', playlist.map((e) => e.path).toList());
    if (currentIndex != null) _prefs.setInt('lastIndex', currentIndex!);
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
    _prefs.setInt('lastIndex', index);
    _loadCurrent(subtune: subtune, autoplay: true);
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
    if (i != null && i.currentSubtune < i.subtunes) selectSubtune(i.currentSubtune + 1);
  }

  void previousSubtune() {
    final i = info;
    if (i != null && i.currentSubtune > 1) selectSubtune(i.currentSubtune - 1);
  }

  void nextTrack() {
    if (playlist.isEmpty) return;
    if (shuffle && playlist.length > 1) {
      final now = DateTime.now().microsecondsSinceEpoch;
      var n = now % playlist.length;
      if (n == currentIndex) n = (n + 1) % playlist.length;
      playIndex(n);
      return;
    }
    final next = (currentIndex ?? -1) + 1;
    if (next < playlist.length) {
      playIndex(next);
    } else {
      stop();
    }
  }

  void previousTrack() {
    if (positionMs > 3000 && info != null) {
      selectSubtune(info!.currentSubtune); // restart
      return;
    }
    final prev = (currentIndex ?? 0) - 1;
    if (prev >= 0) playIndex(prev);
  }

  // ------------------------------------------------------- visual data
  Int16List scope(int frames) => _engine?.scope(frames) ?? Int16List(0);
  Uint8List? sidRegisters(int chip) => _engine?.sidRegisters(chip);

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
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
