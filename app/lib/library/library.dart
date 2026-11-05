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
  const ScanProgress(this.done, this.total, this.phase, {this.slowFile});
  final int done;
  final int total;
  final String phase;

  /// The file being read, when reading it has taken more than a few seconds.
  final String? slowFile;
}

/// Why a file or folder was left out of the last refresh.
enum ScanIssueKind {
  folder, // a folder could not be opened
  unreadable, // a file could not be read from the disk
  notATune, // read, but no player recognised it
  timedOut, // reading its tune info did not finish
  crashed; // reading it stopped the scanner

  String get label => switch (this) {
    folder => 'Folder could not be opened',
    unreadable => 'File could not be read',
    notATune => 'Not recognised as a tune',
    timedOut => 'Took too long to read',
    crashed => 'Stopped the scanner',
  };

  static ScanIssueKind fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : notATune;
}

class ScanIssue {
  const ScanIssue(
    this.path,
    this.kind,
    this.detail, {
    this.size = -1,
    this.mtime = -1,
  });
  final String path;
  final ScanIssueKind kind;
  final String detail;
  final int size; // of a file that timed out, so it is skipped until it changes
  final int mtime;

  List<Object> toJson() => [path, kind.index, detail, size, mtime];

  static ScanIssue fromJson(List<dynamic> j) => ScanIssue(
    j[0] as String,
    ScanIssueKind.fromIndex(j[1] as int),
    j[2] as String,
    size: j.length > 3 ? j[3] as int : -1,
    mtime: j.length > 4 ? j[4] as int : -1,
  );
}

/// How long reading one file's tune info may take before the scan gives up
/// on it and moves on.
Duration probeTimeout = const Duration(seconds: 20);

/// After this many files that hang, a refresh stops reading new files (each
/// one leaves a stuck background thread until the app is closed).
const maxHungFiles = 5;

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

  /// Files and folders the refreshes left out, with the reason. Only the
  /// latest refresh of each location counts.
  List<ScanIssue> scanIssues = [];

  /// Set with [message] when the refresh that wrote it had problems, so the
  /// app can offer the scan report.
  bool messageHasIssues = false;

  _ScanRun? _run;

  /// Locations waiting for the running refresh to finish.
  final List<String> queuedRoots = [];
  bool _queuedFull = false;

  /// Called when a location contains an HVSC Songlengths.md5 file.
  void Function(String path)? onSonglengthsFound;
  String? Function()? songlengthsPath;

  /// Called when a location contains HVSC STIL.txt (tune information).
  void Function(String path)? onStilFound;
  String? Function()? stilPath;

  @visibleForTesting
  static LibraryController forIndex(File file) => LibraryController._(file);

  @visibleForTesting
  Future<void> reload() => _load();

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
      final is_ = data['issues'];
      if (is_ is List) {
        scanIssues = [for (final i in is_) ScanIssue.fromJson(i as List)];
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
      'issues': [for (final i in scanIssues) i.toJson()],
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
    queuedRoots.remove(dir);
    scanIssues = [
      for (final i in scanIssues)
        if (!p.isWithin(dir, i.path) && !p.equals(dir, i.path)) i,
    ];
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
    if (targets.isEmpty) return;
    if (isScanning) {
      // A location added (or a refresh asked for) while another refresh
      // runs is queued and refreshed right after it.
      for (final t in targets) {
        if (!scanningRoots.contains(t) && !queuedRoots.contains(t)) {
          queuedRoots.add(t);
        }
      }
      _queuedFull |= full;
      notifyListeners();
      return;
    }
    final run = _ScanRun();
    _run = run;
    scanningRoots = targets;
    final where = targets.length == 1 && roots.length > 1
        ? ' in ${p.basename(targets.first)}'
        : '';
    scan = ScanProgress(0, 0, 'Looking for tunes$where…');
    notifyListeners();

    bool inTargets(String path) =>
        targets.any((r) => p.isWithin(r, path) || p.equals(r, path));
    final known = <String, List<Object>>{
      for (final t in tracks)
        if (inTargets(t.path)) t.path: t.toJson(),
    };
    // Files that hung last time are skipped until they change (a rebuild
    // tries them again).
    final hung = <String, List<int>>{
      if (!full)
        for (final i in scanIssues)
          if (i.kind == ScanIssueKind.timedOut && inTargets(i.path))
            i.path: [i.size, i.mtime],
    };

    try {
      // 1. Find the files.
      final listed = await _listFiles(run, targets, where);
      if (run.cancelled || listed == null) {
        message = 'Refresh cancelled; the library was not changed.';
        messageHasIssues = false;
        return;
      }
      // 2. Read their tune info, a file at a time, with a time limit each.
      final result = await _probeFiles(run, listed.files, known, hung, full);
      if (run.cancelled) {
        message = 'Refresh cancelled; the library was not changed.';
        messageHasIssues = false;
        return;
      }

      final issues = [...listed.issues, ...result.issues];
      // Keep the old entries of locations and folders that could not be
      // read (offline drive, SD card removed, permission revoked), and of
      // files never reached because too many files hung.
      final keepUnder = [...listed.unreadableRoots, ...listed.badDirs];
      final seen = {...listed.files};
      final kept = <List<Object>>[];
      for (final e in known.entries) {
        final under = keepUnder.any((d) => p.isWithin(d, e.key));
        if ((!seen.contains(e.key) && under) ||
            result.notReached.contains(e.key)) {
          kept.add(e.value);
        }
      }
      final fresh = [
        for (final t in [...result.tracks, ...kept]) LibraryTrack.fromJson(t),
      ];
      tracks = [
        for (final t in tracks)
          if (!inTargets(t.path)) t,
        ...fresh,
      ];
      scanIssues = [
        for (final i in scanIssues)
          if (!inTargets(i.path)) i,
        ...issues,
      ];
      final now = DateTime.now();
      lastScan = now;
      for (final r in targets) {
        if (!listed.unreadableRoots.contains(r)) rootScans[r] = now;
      }
      _rebuildFolders();
      final what = targets.length == 1 && roots.length > 1
          ? p.basename(targets.first)
          : 'Library';
      final count = targets.length == roots.length
          ? tracks.length
          : fresh.length;
      final added = result.changed;
      final parts = <String>[
        added > 0
            ? '$what updated: $count tunes ($added new or changed).'
            : '$what is up to date: $count tunes.',
      ];
      if (listed.unreadableRoots.isNotEmpty) {
        parts.add(
          listed.unreadableRoots.length == 1
              ? 'Could not open ${listed.unreadableRoots.first}.'
              : 'Could not open ${listed.unreadableRoots.length} locations.',
        );
      }
      if (result.gaveUp) {
        parts.add('Stopped reading new files after $maxHungFiles hung.');
      }
      if (issues.isNotEmpty) {
        parts.add(
          '${issues.length} ${issues.length == 1 ? 'file or folder was' : 'files or folders were'} skipped.',
        );
      }
      message = parts.join(' ');
      messageHasIssues = issues.isNotEmpty;
    } catch (e) {
      message = 'Refresh failed: $e';
      messageHasIssues = false;
    } finally {
      run.dispose();
      _run = null;
      scan = null;
      scanningRoots = const [];
      notifyListeners();
      if (!run.cancelled) await _save();
    }
    if (queuedRoots.isNotEmpty) {
      final next = [...queuedRoots];
      final nextFull = _queuedFull;
      queuedRoots.clear();
      _queuedFull = false;
      if (run.cancelled) {
        notifyListeners();
      } else {
        await rescan(full: nextFull, only: next);
      }
    }
  }

  /// Stops the running refresh. The library keeps what it had before.
  void cancelScan() {
    final run = _run;
    if (run == null || run.cancelled) return;
    run.cancel();
    queuedRoots.clear();
    _queuedFull = false;
    scan = ScanProgress(0, 0, 'Cancelling…');
    notifyListeners();
  }

  Future<_Listed?> _listFiles(
    _ScanRun run,
    List<String> targets,
    String where,
  ) async {
    final port = run.newPort();
    final isolate = await Isolate.spawn(
      _listWorker,
      _ListArgs(port.sendPort, targets),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    run.isolate = isolate;
    final out = Completer<_Listed?>();
    run.onCancel = () {
      if (!out.isCompleted) out.complete(null);
    };
    var lastUi = DateTime.now();
    port.listen((msg) {
      if (out.isCompleted) return;
      if (msg is List && msg.isNotEmpty && msg[0] == 'dir') {
        final now = DateTime.now();
        if (now.difference(lastUi).inMilliseconds < 150) return;
        lastUi = now;
        scan = ScanProgress(
          0,
          0,
          'Looking for tunes$where… ${msg[2]} found in ${msg[1]} folders',
        );
        notifyListeners();
      } else if (msg is List && msg.isNotEmpty && msg[0] == 'listed') {
        out.complete(
          _Listed(
            (msg[1] as List).cast<String>(),
            (msg[2] as List).cast<String>(),
            [
              for (final b in msg[3] as List)
                ScanIssue(
                  (b as List)[0] as String,
                  ScanIssueKind.folder,
                  b[1] as String,
                ),
            ],
          ),
        );
      } else {
        // An error ([error, stack]) or the isolate exiting without a result.
        out.completeError(
          msg is List && msg.isNotEmpty
              ? 'could not list the folders (${msg.first})'
              : 'could not list the folders',
        );
      }
    });
    return out.future;
  }

  Future<_Probed> _probeFiles(
    _ScanRun run,
    List<String> files,
    Map<String, List<Object>> known,
    Map<String, List<int>> hung,
    bool full,
  ) async {
    final result = _Probed();
    final songlengths = songlengthsPath?.call();
    var next = 0; // index of the first file without a result
    var hungFiles = 0;
    scan = ScanProgress(0, files.length, 'Indexing');
    notifyListeners();

    while (next < files.length && !run.cancelled) {
      // One worker reads files from [next] on. If a file hangs, the worker
      // is abandoned and a new one carries on after that file.
      final port = run.newPort();
      final done = Completer<String>(); // why the worker stopped
      var lastMsg = DateTime.now();
      var lastUi = DateTime.now();
      port.listen((msg) {
        if (done.isCompleted) return;
        lastMsg = DateTime.now();
        if (msg is List && msg.isNotEmpty && msg[0] == 'r') {
          final i = msg[1] as int;
          final track = msg[2];
          if (track is List) {
            result.tracks.add(track.cast<Object>());
          } else if (msg[3] is List) {
            result.issues.add(ScanIssue.fromJson(msg[3] as List));
          }
          if (msg[4] == true) result.changed++;
          next = i + 1;
          final now = DateTime.now();
          if (now.difference(lastUi).inMilliseconds >= 150 ||
              next == files.length) {
            lastUi = now;
            scan = ScanProgress(next, files.length, 'Indexing');
            notifyListeners();
          }
        } else if (msg is List && msg.isNotEmpty && msg[0] == 'end') {
          done.complete('end');
        } else if (msg == null) {
          done.complete('exit'); // onExit without 'end': it died
        } else if (msg is List) {
          done.complete('error: ${msg.first}');
        }
      });
      run.isolate = await Isolate.spawn(
        _probeWorker,
        _ProbeArgs(port.sendPort, files, next, known, hung, full, songlengths),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      run.onCancel = () {
        if (!done.isCompleted) done.complete('cancel');
      };
      // Watchdog: notice a file that takes too long, and show which file it
      // is after a few seconds so a slow drive is not mistaken for a hang.
      final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (done.isCompleted || next >= files.length) return;
        final quiet = DateTime.now().difference(lastMsg);
        if (quiet >= probeTimeout) {
          done.complete('timeout');
        } else if (quiet >= const Duration(seconds: 3)) {
          scan = ScanProgress(
            next,
            files.length,
            'Indexing',
            slowFile: files[next],
          );
          notifyListeners();
        }
      });
      final why = await done.future;
      timer.cancel();
      if (why == 'end' || why == 'cancel') break;
      // The worker is stuck in (or died reading) files[next]: drop it, note
      // the file and carry on with the one after.
      run.killIsolate();
      if (next >= files.length) break;
      final bad = files[next];
      var size = -1, mtime = -1;
      try {
        final st = File(bad).statSync();
        size = st.size;
        mtime = st.modified.millisecondsSinceEpoch;
      } catch (_) {}
      if (why == 'timeout') {
        hungFiles++;
        result.issues.add(
          ScanIssue(
            bad,
            ScanIssueKind.timedOut,
            'Reading its tune info took over ${probeTimeout.inSeconds} s; '
            'skipped until the file changes.',
            size: size,
            mtime: mtime,
          ),
        );
      } else {
        result.issues.add(
          ScanIssue(bad, ScanIssueKind.crashed, 'The scanner stopped ($why).'),
        );
      }
      next++;
      if (hungFiles >= maxHungFiles) {
        result.gaveUp = true;
        result.notReached.addAll(files.skip(next));
        break;
      }
    }
    return result;
  }

  // ------------------------------------------------------------ browse/search
  void _rebuildFolders() {
    _folders.clear();
    _byPathFor = null;
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

  /// The indexed details of the tune at [path], or null when it is not in
  /// the library. Used to show titles in favourites and playlists.
  TuneInfo? infoFor(String path) {
    if (!identical(_byPathFor, tracks)) {
      _byPathFor = tracks;
      _byPath = {for (final t in tracks) t.path: t};
    }
    return _byPath[path]?.toInfo();
  }

  List<LibraryTrack>? _byPathFor;
  Map<String, LibraryTrack> _byPath = const {};

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

class _ScanRun {
  final List<ReceivePort> _ports = [];
  Isolate? isolate;
  bool cancelled = false;
  void Function()? onCancel;

  ReceivePort newPort() {
    final port = ReceivePort();
    _ports.add(port);
    return port;
  }

  void killIsolate() {
    // A worker stuck inside native code does not stop until that code
    // returns; it is abandoned (its port is closed, so nothing it sends
    // later is read).
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
  }

  void cancel() {
    cancelled = true;
    killIsolate();
    onCancel?.call();
  }

  void dispose() {
    killIsolate();
    for (final p in _ports) {
      p.close();
    }
    _ports.clear();
  }
}

class _Listed {
  _Listed(this.files, this.unreadableRoots, this.issues);
  final List<String> files;
  final List<String> unreadableRoots;
  final List<ScanIssue> issues; // folders that could not be opened
  List<String> get badDirs => [for (final i in issues) i.path];
}

class _Probed {
  final List<List<Object>> tracks = [];
  final List<ScanIssue> issues = [];
  final Set<String> notReached = {};
  int changed = 0;
  bool gaveUp = false;
}

class _ListArgs {
  _ListArgs(this.port, this.roots);
  final SendPort port;
  final List<String> roots;
}

/// Lists the tunes below [roots], one folder at a time, so a folder that
/// cannot be opened (permissions, a name Windows cannot handle, a path that
/// is too long, a network error) is reported and skipped instead of
/// failing the whole location.
void _listWorker(_ListArgs a) {
  final files = <String>[];
  final unreadable = <String>[];
  final badDirs = <List<String>>[];
  var folders = 0;
  var lastSend = DateTime.now();
  for (final r in a.roots) {
    try {
      if (!Directory(r).existsSync()) {
        unreadable.add(r);
        continue;
      }
    } catch (_) {
      unreadable.add(r);
      continue;
    }
    final stack = <String>[r];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      folders++;
      final subdirs = <String>[];
      try {
        for (final e in Directory(dir).listSync(followLinks: false)) {
          if (e is Directory) {
            subdirs.add(e.path);
          } else if (e is File && isSupportedFile(e.path)) {
            files.add(e.path);
          }
        }
      } on FileSystemException catch (e) {
        if (p.equals(dir, r)) {
          unreadable.add(r);
        } else {
          badDirs.add([dir, _describe(e)]);
        }
      } catch (e) {
        if (p.equals(dir, r)) {
          unreadable.add(r);
        } else {
          badDirs.add([dir, '$e']);
        }
      }
      // Depth first, in name order.
      subdirs.sort((x, y) => y.toLowerCase().compareTo(x.toLowerCase()));
      stack.addAll(subdirs);
      final now = DateTime.now();
      if (now.difference(lastSend).inMilliseconds >= 100) {
        lastSend = now;
        a.port.send(['dir', folders, files.length]);
      }
    }
  }
  Isolate.exit(a.port, ['listed', files, unreadable, badDirs]);
}

String _describe(FileSystemException e) {
  final os = e.osError;
  if (os != null && os.message.isNotEmpty) {
    return '${os.message.trim()} (error ${os.errorCode})';
  }
  return e.message;
}

class _ProbeArgs {
  _ProbeArgs(
    this.port,
    this.files,
    this.start,
    this.known,
    this.hung,
    this.full,
    this.songlengths,
  );
  final SendPort port;
  final List<String> files;
  final int start;
  final Map<String, List<Object>> known;
  final Map<String, List<int>> hung; // path: [size, mtime]
  final bool full; // re-read every file instead of reusing unchanged ones
  final String? songlengths;
}

/// Reads the tune info of files[start..], sending one result per file:
/// ['r', index, track json or null, issue json or null, changed].
void _probeWorker(_ProbeArgs a) {
  final native = ChipDeckNative.open();
  for (var i = a.start; i < a.files.length; i++) {
    final path = a.files[i];
    List<Object>? track;
    List<Object>? issue;
    var changed = false;
    try {
      final st = File(path).statSync();
      if (st.type == FileSystemEntityType.notFound) {
        throw FileSystemException('The file is gone', path);
      }
      final size = st.size;
      final mtime = st.modified.millisecondsSinceEpoch;
      final old = a.full ? null : a.known[path];
      final h = a.hung[path];
      if (old != null && old[7] == size && old[8] == mtime) {
        track = old;
      } else if (h != null && h[0] == size && h[1] == mtime) {
        issue = ScanIssue(
          path,
          ScanIssueKind.timedOut,
          'Took too long to read last time; skipped until the file changes '
          '(Rebuild index tries it again).',
          size: size,
          mtime: mtime,
        ).toJson();
      } else {
        final info = native.probe(path, songlengths: a.songlengths);
        if (info != null) {
          track = LibraryTrack(
            path: path,
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
          ).toJson();
          changed = true;
        } else {
          issue = ScanIssue(
            path,
            ScanIssueKind.notATune,
            size == 0
                ? 'The file is empty.'
                : 'No player recognised it (damaged, or a variant ChipDeck '
                      'cannot play).',
          ).toJson();
        }
      }
    } on FileSystemException catch (e) {
      issue = ScanIssue(path, ScanIssueKind.unreadable, _describe(e)).toJson();
    } catch (e) {
      issue = ScanIssue(path, ScanIssueKind.unreadable, '$e').toJson();
    }
    a.port.send(['r', i, track, issue, changed]);
  }
  a.port.send(['end']);
}
