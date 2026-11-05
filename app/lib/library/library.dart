// Music library: saved archive locations, a persistent index, browse and search.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
//
// The index is a JSON file in the app support folder. Rescans are
// incremental: files whose size and modification time did not change keep
// their metadata, so only new or changed files are probed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../hvsc/stil.dart';
import '../native/chipdeck_ffi.dart';
import '../player/player_controller.dart' show isSupportedFile;

class LibraryTrack {
  LibraryTrack({
    required this.path,
    required this.title,
    required this.author,
    required this.released,
    required this.format,
    required this.subtunes,
    required this.lengthMs,
    required this.size,
    required this.mtime,
    required this.sidChips,
    required this.system,
  });

  final String path;
  final String title;
  final String author;
  final String released;
  final String format;
  final int subtunes;
  final int lengthMs; // -1 if unknown
  final int size;
  final int mtime; // ms since epoch
  final int sidChips; // 0 for non-SID (Atari, modules)
  final TuneSystem system;

  String get fileName => p.basename(path);
  String get displayTitle =>
      title.isNotEmpty ? title : p.basenameWithoutExtension(path);

  /// Short format label for badges.
  String get kind {
    switch (system) {
      case TuneSystem.atariSt:
        if (format.contains('TFMX')) return 'TFMX';
        final ext = p.extension(path).toLowerCase();
        return ext == '.ym' ? 'YM' : 'SNDH';
      case TuneSystem.amiga:
        if (format.contains('Future Composer')) return 'FC';
        if (format.contains('TFMX')) return 'TFMX';
        return 'MOD';
      case TuneSystem.pc:
        return 'XM';
      case TuneSystem.c64:
        return format.contains('RSID') ? 'RSID' : 'SID';
    }
  }

  bool get isModule => system == TuneSystem.amiga || system == TuneSystem.pc;

  late final String formatKey = libraryFormatKey(system, kind);

  late final String _blob =
      '$title\n$author\n$released\n${p.basename(path)}\n${p.basename(p.dirname(path))}'
          .toLowerCase();

  bool matches(List<String> tokens) {
    for (final t in tokens) {
      if (!_blob.contains(t)) return false;
    }
    return true;
  }

  TuneInfo toInfo() => TuneInfo(
    title: title,
    author: author,
    released: released,
    format: format,
    subtunes: subtunes,
    startSubtune: 1,
    currentSubtune: 1,
    sidChips: sidChips,
    sidModel: SidModel.auto,
    isNtsc: false,
    lengthMs: lengthMs > 0 ? lengthMs : null,
    system: system,
  );

  List<Object> toJson() => [
    path,
    title,
    author,
    released,
    format,
    subtunes,
    lengthMs,
    size,
    mtime,
    sidChips,
    system.index,
  ];

  static LibraryTrack fromJson(List<dynamic> j) => LibraryTrack(
    path: j[0] as String,
    title: j[1] as String,
    author: j[2] as String,
    released: j[3] as String,
    format: j[4] as String,
    subtunes: j[5] as int,
    lengthMs: j[6] as int,
    size: j[7] as int,
    mtime: j[8] as int,
    sidChips: j.length > 9 ? j[9] as int : 1,
    // Indexes from before 0.6.0 have no system: sidChips 0 meant Atari.
    system: j.length > 10
        ? TuneSystem.fromIndex(j[10] as int)
        : (j.length > 9 && j[9] == 0 ? TuneSystem.atariSt : TuneSystem.c64),
  );
}

/// A folder in the browse view.
class LibraryFolder {
  LibraryFolder(this.path);
  final String path;
  final List<String> children = []; // sub-folder paths
  final List<int> tracks = []; // indices into LibraryController.tracks
  int totalTracks = 0; // including sub-folders

  String get name => p.basename(path);
}

/// One format the library can filter on. Formats are grouped by system;
/// the same short name can appear under two systems (TFMX on the Amiga and
/// TFMX-ST on the Atari ST), so a format is identified by both.
class TuneFormat {
  const TuneFormat(this.system, this.kind, this.label);
  final TuneSystem system;
  final String kind; // as LibraryTrack.kind
  final String label; // shown in the filter menu
  String get key => libraryFormatKey(system, kind);
}

String libraryFormatKey(TuneSystem system, String kind) =>
    '${system.name}/$kind';

/// Every format the filter offers, by system. A new format only needs a
/// line here (and a case in LibraryTrack.kind).
const formatGroups = <(TuneSystem, String, List<TuneFormat>)>[
  (
    TuneSystem.c64,
    'Commodore 64',
    [
      TuneFormat(TuneSystem.c64, 'SID', 'SID (PSID)'),
      TuneFormat(TuneSystem.c64, 'RSID', 'RSID'),
    ],
  ),
  (
    TuneSystem.atariSt,
    'Atari ST',
    [
      TuneFormat(TuneSystem.atariSt, 'SNDH', 'SNDH'),
      TuneFormat(TuneSystem.atariSt, 'YM', 'YM'),
      TuneFormat(TuneSystem.atariSt, 'TFMX', 'TFMX-ST'),
    ],
  ),
  (
    TuneSystem.amiga,
    'Amiga',
    [
      TuneFormat(TuneSystem.amiga, 'MOD', 'MOD'),
      TuneFormat(TuneSystem.amiga, 'TFMX', 'TFMX'),
      TuneFormat(TuneSystem.amiga, 'FC', 'Future Composer'),
    ],
  ),
  (TuneSystem.pc, 'PC', [TuneFormat(TuneSystem.pc, 'XM', 'XM')]),
];

/// Library format filter: a set of format keys. Empty means every format.
@immutable
class FormatFilter {
  const FormatFilter([this.keys = const {}]);
  static const all = FormatFilter();

  final Set<String> keys;

  bool get isAll => keys.isEmpty;
  bool accepts(LibraryTrack t) => keys.isEmpty || keys.contains(t.formatKey);

  /// All formats of [system] selected (none selected counts as no).
  bool hasSystem(TuneSystem system) => _systemKeys(system).every(keys.contains);

  FormatFilter toggle(String key) {
    final k = {...keys};
    if (!k.remove(key)) k.add(key);
    return FormatFilter(_normalise(k));
  }

  FormatFilter toggleSystem(TuneSystem system) {
    final sk = _systemKeys(system);
    final k = {...keys};
    if (hasSystem(system)) {
      k.removeAll(sk);
    } else {
      k.addAll(sk);
    }
    return FormatFilter(_normalise(k));
  }

  /// Short description for the filter button, e.g. "C64 + ST" or "SNDH, YM".
  String get summary {
    if (isAll) return 'All formats';
    final parts = <String>[];
    for (final (sys, _, formats) in formatGroups) {
      if (hasSystem(sys) && formats.length > 1) {
        parts.add(sys.label);
      } else {
        for (final f in formats) {
          if (keys.contains(f.key)) parts.add(f.label);
        }
      }
    }
    if (parts.length > 3) return '${keys.length} formats';
    return parts.join(', ');
  }

  // Every format selected is the same as no filter.
  static Set<String> _normalise(Set<String> k) {
    final every = [
      for (final g in formatGroups)
        for (final f in g.$3) f.key,
    ];
    return every.every(k.contains) ? const {} : Set.unmodifiable(k);
  }

  static Iterable<String> _systemKeys(TuneSystem system) => formatGroups
      .where((g) => g.$1 == system)
      .expand((g) => g.$3)
      .map((f) => f.key);

  List<String> toJson() => keys.toList()..sort();

  static FormatFilter fromJson(List<String>? j) =>
      j == null ? all : FormatFilter(_normalise(j.toSet()));

  @override
  bool operator ==(Object other) =>
      other is FormatFilter &&
      other.keys.length == keys.length &&
      other.keys.containsAll(keys);

  @override
  int get hashCode => Object.hashAllUnordered(keys);
}

class ScanProgress {
  const ScanProgress(this.done, this.total, this.phase);
  final int done;
  final int total;
  final String phase;
}

class LibraryController extends ChangeNotifier {
  LibraryController._(this._file);

  final File _file;
  final List<String> roots = [];
  List<LibraryTrack> tracks = [];
  final Map<String, LibraryFolder> _folders = {};
  ScanProgress? scan; // non-null while indexing
  DateTime? lastScan;

  /// When each location was last refreshed.
  final Map<String, DateTime> rootScans = {};

  /// Locations being refreshed right now (empty when idle).
  List<String> scanningRoots = const [];
  String? message;

  /// Called when a location contains an HVSC Songlengths.md5 file.
  void Function(String path)? onSonglengthsFound;
  String? Function()? songlengthsPath;

  /// Called when a location contains HVSC STIL.txt (tune information).
  void Function(String path)? onStilFound;
  String? Function()? stilPath;

  static Future<LibraryController> create() async {
    final dir = await getApplicationSupportDirectory();
    final c = LibraryController._(File(p.join(dir.path, 'library.json')));
    await c._load();
    return c;
  }

  bool get isScanning => scan != null;

  // ------------------------------------------------------------ persistence
  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      final data = await Isolate.run(() => _decode(_file.path));
      roots
        ..clear()
        ..addAll((data['roots'] as List).cast<String>());
      tracks = [
        for (final t in data['tracks'] as List)
          LibraryTrack.fromJson(t as List),
      ];
      final ls = data['lastScan'];
      if (ls is int) lastScan = DateTime.fromMillisecondsSinceEpoch(ls);
      final rs = data['rootScans'];
      if (rs is Map) {
        for (final e in rs.entries) {
          if (e.value is int) {
            rootScans[e.key as String] = DateTime.fromMillisecondsSinceEpoch(
              e.value as int,
            );
          }
        }
      }
      _rebuildFolders();
    } catch (e) {
      debugPrint('library load failed: $e');
    }
  }

  Future<void> _save() async {
    final json = jsonEncode({
      'version': 1,
      'roots': roots,
      'lastScan': lastScan?.millisecondsSinceEpoch,
      'rootScans': {
        for (final e in rootScans.entries)
          e.key: e.value.millisecondsSinceEpoch,
      },
      'tracks': [for (final t in tracks) t.toJson()],
    });
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(json);
    await tmp.rename(_file.path);
  }

  // -------------------------------------------------------------- locations
  Future<void> addRoot(String dir) async {
    final norm = p.normalize(dir);
    if (roots.any((r) => p.equals(r, norm) || p.isWithin(r, norm))) {
      message = 'That folder is already in your library.';
      notifyListeners();
      return;
    }
    // A new root may contain existing roots; fold them in.
    roots.removeWhere((r) => p.isWithin(norm, r));
    rootScans.removeWhere((r, _) => p.isWithin(norm, r));
    roots.add(norm);
    roots.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _detectSonglengths(norm);
    if (stilPath?.call() == null) {
      final stil = StilDatabase.find(norm);
      if (stil != null) onStilFound?.call(stil);
    }
    notifyListeners();
    // Only the new location needs reading; the others are left as they are.
    await rescan(only: [norm]);
  }

  Future<void> removeRoot(String dir) async {
    roots.remove(dir);
    rootScans.remove(dir);
    tracks = tracks.where((t) => !p.isWithin(dir, t.path)).toList();
    _rebuildFolders();
    notifyListeners();
    await _save();
  }

  void _detectSonglengths(String root) {
    if (songlengthsPath?.call() != null) return;
    final candidates = [
      p.join(root, 'DOCUMENTS', 'Songlengths.md5'),
      p.join(root, 'C64Music', 'DOCUMENTS', 'Songlengths.md5'),
      p.join(p.dirname(root), 'DOCUMENTS', 'Songlengths.md5'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        onSonglengthsFound?.call(c);
        return;
      }
    }
  }

  // ---------------------------------------------------------------- indexing
  /// Refreshes the index. The library is never refreshed on its own (not
  /// even at startup): this runs when the user asks, when a location is
  /// added, or after a new Songlengths file.
  ///
  /// [only] limits the refresh to those locations (default: all of them);
  /// tunes in other locations are left untouched. [full] re-reads every file
  /// (e.g. after adding a Songlengths database), otherwise unchanged files
  /// are skipped.
  Future<void> rescan({bool full = false, List<String>? only}) async {
    final targets = [
      for (final r in only ?? roots)
        if (roots.contains(r)) r,
    ];
    if (isScanning || targets.isEmpty) return;
    scanningRoots = targets;
    scan = ScanProgress(
      0,
      0,
      targets.length == 1 && roots.length > 1
          ? 'Looking for tunes in ${p.basename(targets.first)}…'
          : 'Looking for tunes…',
    );
    notifyListeners();

    bool inTargets(String path) => targets.any((r) => p.isWithin(r, path));
    final known = <String, List<Object>>{
      for (final t in tracks)
        if (inTargets(t.path)) t.path: t.toJson(),
    };
    final port = ReceivePort();
    final args = _ScanArgs(
      port.sendPort,
      targets,
      known,
      full,
      songlengthsPath?.call(),
    );
    await Isolate.spawn(
      _scanWorker,
      args,
      errorsAreFatal: true,
      onError: port.sendPort,
    );

    final done = Completer<void>();
    port.listen((msg) {
      if (msg is List && msg.isNotEmpty && msg[0] == 'progress') {
        scan = ScanProgress(msg[1] as int, msg[2] as int, 'Indexing');
        notifyListeners();
      } else if (msg is List && msg.isNotEmpty && msg[0] == 'done') {
        final fresh = [
          for (final t in msg[1] as List) LibraryTrack.fromJson(t as List),
        ];
        tracks = [
          for (final t in tracks)
            if (!inTargets(t.path)) t,
          ...fresh,
        ];
        final added = msg[2] as int;
        final now = DateTime.now();
        lastScan = now;
        for (final r in targets) {
          rootScans[r] = now;
        }
        _rebuildFolders();
        final what = targets.length == 1 && roots.length > 1
            ? p.basename(targets.first)
            : 'Library';
        final count = targets.length == roots.length
            ? tracks.length
            : fresh.length;
        message = added > 0
            ? '$what updated: $count tunes ($added new or changed).'
            : '$what is up to date: $count tunes.';
        port.close();
        done.complete();
      } else if (msg is List) {
        // Error from the isolate: [error, stack]
        message = 'Indexing failed: ${msg.first}';
        port.close();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
    scan = null;
    scanningRoots = const [];
    notifyListeners();
    await _save();
  }

  // ------------------------------------------------------------ browse/search
  void _rebuildFolders() {
    _folders.clear();
    tracks.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final r in roots) {
      _folders[r] = LibraryFolder(r);
    }
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final root = roots.firstWhere(
        (r) => p.isWithin(r, t.path),
        orElse: () => '',
      );
      if (root.isEmpty) continue;
      var dir = p.dirname(t.path);
      _folder(dir).tracks.add(i);
      // Walk up to the root, linking folders and counting tracks.
      while (true) {
        _folder(dir).totalTracks++;
        if (p.equals(dir, root)) break;
        final parent = p.dirname(dir);
        final pf = _folder(parent);
        if (!pf.children.contains(dir)) pf.children.add(dir);
        dir = parent;
      }
    }
    for (final f in _folders.values) {
      f.children.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
  }

  LibraryFolder _folder(String path) =>
      _folders.putIfAbsent(path, () => LibraryFolder(path));

  LibraryFolder? folder(String path) => _folders[path];

  /// All tracks below [dir], in path order.
  List<LibraryTrack> tracksUnder(String dir) => [
    for (final t in tracks)
      if (p.isWithin(dir, t.path)) t,
  ];

  /// How many tunes of each format the library holds (by format key).
  Map<String, int> get formatCounts {
    final key = (identityHashCode(tracks), tracks.length);
    if (key != _countsKey) {
      final m = <String, int>{};
      for (final t in tracks) {
        m[t.formatKey] = (m[t.formatKey] ?? 0) + 1;
      }
      _counts = m;
      _countsKey = key;
    }
    return _counts;
  }

  Map<String, int> _counts = const {};
  Object? _countsKey;

  List<LibraryTrack> search(
    String query, {
    FormatFilter filter = FormatFilter.all,
    int limit = 1000,
  }) {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final out = <LibraryTrack>[];
    for (final t in tracks) {
      if (!filter.accepts(t)) continue;
      if (tokens.isNotEmpty && !t.matches(tokens)) continue;
      out.add(t);
      if (out.length >= limit) break;
    }
    return out;
  }
}

Map<String, dynamic> _decode(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

class _ScanArgs {
  _ScanArgs(this.port, this.roots, this.known, this.full, this.songlengths);
  final SendPort port;
  final List<String> roots;
  final Map<String, List<Object>> known;
  final bool full; // re-read every file instead of reusing unchanged ones
  final String? songlengths;
}

void _scanWorker(_ScanArgs a) {
  final files = <File>[];
  // Locations that could not be read (offline drive, SD card removed, storage
  // permission revoked on Android): keep their old index instead of
  // dropping every tune in them.
  final unreadable = <String>[];
  for (final r in a.roots) {
    try {
      if (!Directory(r).existsSync()) {
        unreadable.add(r);
        continue;
      }
      for (final e in Directory(
        r,
      ).listSync(recursive: true, followLinks: false)) {
        if (e is File && isSupportedFile(e.path)) {
          files.add(e);
        }
      }
    } catch (_) {
      unreadable.add(r);
    }
  }
  a.port.send(['progress', 0, files.length]);

  final native = ChipDeckNative.open();
  final out = <List<Object>>[];
  var changed = 0;
  final seen = <String>{};
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    try {
      final st = f.statSync();
      final size = st.size;
      final mtime = st.modified.millisecondsSinceEpoch;
      seen.add(f.path);
      final old = a.full ? null : a.known[f.path];
      if (old != null && old[7] == size && old[8] == mtime) {
        out.add(old);
      } else {
        final info = native.probe(f.path, songlengths: a.songlengths);
        if (info != null) {
          out.add(
            LibraryTrack(
              path: f.path,
              title: info.title,
              author: info.author,
              released: info.released,
              format: info.format,
              subtunes: info.subtunes,
              lengthMs: info.lengthMs ?? -1,
              size: size,
              mtime: mtime,
              sidChips: info.sidChips,
              system: info.system,
            ).toJson(),
          );
          changed++;
        }
      }
    } catch (_) {}
    if (i % 250 == 0) a.port.send(['progress', i, files.length]);
  }
  for (final e in a.known.entries) {
    if (!seen.contains(e.key) && unreadable.any((r) => p.isWithin(r, e.key))) {
      out.add(e.value);
    }
  }
  Isolate.exit(a.port, ['done', out, changed]);
}
