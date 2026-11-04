// HVSC STIL.txt (SID Tune Information List) and BUGlist.txt reader.
//
// Both files share one format: an entry starts with an HVSC path on its own
// line ("/MUSICIANS/H/Hubbard_Rob/Commando.sid", or a folder ending in "/"),
// followed by fields ("   TITLE: ...", " COMMENT: ...", "     BUG: ...").
// "(#n)" lines start the fields for subtune n; fields before the first one
// are about the whole file. Lines indented by 9 spaces continue the field
// above. A blank line ends the entry, "#" lines are comments. The files are
// ISO-8859-1.
//
// Parsing is done in Dart (not the C++ core) because it is plain text and
// only the UI uses it. Only the raw text of each entry is kept in memory;
// fields are parsed when an entry is looked up.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// One field of an entry, e.g. ("TITLE", "Commando (theme)").
class StilField {
  const StilField(this.key, this.value);
  final String key;
  final String value;

  /// Display label: "Title", "Artist", ...
  String get label =>
      key.isEmpty ? '' : key[0].toUpperCase() + key.substring(1).toLowerCase();
}

/// A parsed entry: fields for the whole file (subtune 0) and per subtune.
class StilEntry {
  StilEntry(this.path, this.blocks);
  final String path;

  /// Subtune number -> fields in file order. 0 is the whole file.
  final Map<int, List<StilField>> blocks;

  List<StilField> get global => blocks[0] ?? const [];
  List<StilField> subtune(int n) => blocks[n] ?? const [];
  List<int> get subtunes => (blocks.keys.where((k) => k > 0).toList()..sort());
  bool get isEmpty => blocks.values.every((b) => b.isEmpty);

  static final _subtune = RegExp(r'^\(#(\d+)\)\s*$');
  static final _field = RegExp(r'^\s{0,8}([A-Z]+):\s?(.*)$');

  static StilEntry parse(String path, String raw) {
    final blocks = <int, List<StilField>>{};
    var cur = 0;
    String? key;
    final value = StringBuffer();
    void flush() {
      if (key != null) {
        (blocks[cur] ??= []).add(StilField(key!, value.toString().trim()));
      }
      key = null;
      value.clear();
    }

    for (final line in const LineSplitter().convert(raw)) {
      final sub = _subtune.firstMatch(line);
      if (sub != null) {
        flush();
        cur = int.parse(sub.group(1)!);
        blocks[cur] ??= [];
        continue;
      }
      final f = _field.firstMatch(line);
      if (f != null) {
        flush();
        key = f.group(1);
        value.write(f.group(2)!.trimRight());
        continue;
      }
      if (key == null) continue;
      // Continuation: STIL wraps text at 9 spaces. Deeper indentation is
      // deliberate layout (lists, lyrics), so keep the line break there.
      final text = line.trimRight();
      final indent = text.length - text.trimLeft().length;
      if (indent > 9) {
        value.write('\n${text.substring(9)}');
      } else {
        value.write(' ${text.trimLeft()}');
      }
    }
    flush();
    return StilEntry(path, blocks);
  }
}

/// STIL and BUGlist entries that apply to one tune.
class TuneStil {
  const TuneStil({this.tune, this.folders = const [], this.bugs});

  /// Entry for the file itself.
  final StilEntry? tune;

  /// Entries for the folders above it, nearest first (e.g. the musician's
  /// folder, then a group folder).
  final List<StilEntry> folders;

  /// BUGlist entry: known emulation problems with this tune.
  final StilEntry? bugs;

  bool get isEmpty =>
      (tune?.isEmpty ?? true) &&
      folders.every((f) => f.isEmpty) &&
      (bugs?.isEmpty ?? true);

  /// Title of [subtune] from STIL (e.g. the original song a cover is of).
  String? titleFor(int subtune) {
    for (final f in [...?tune?.subtune(subtune), ...?tune?.global]) {
      if (f.key == 'TITLE' || f.key == 'NAME') return f.value;
    }
    return null;
  }
}

/// STIL.txt plus BUGlist.txt from one HVSC DOCUMENTS folder.
class StilDatabase {
  StilDatabase._(this.stilPath, this.root, this._stil, this._bugs);

  /// Path of STIL.txt.
  final String stilPath;

  /// HVSC root (the folder holding DOCUMENTS, MUSICIANS, GAMES, ...).
  final String root;

  // HVSC path (lower case) -> raw entry text.
  final Map<String, String> _stil;
  final Map<String, String> _bugs;

  int get entryCount => _stil.length;

  /// Reads [stilPath] (and BUGlist.txt next to it) in a background isolate.
  /// Returns null if the file is missing or has no entries.
  static Future<StilDatabase?> load(String stilPath) async {
    final docs = p.dirname(stilPath);
    final bugPath = p.join(docs, 'BUGlist.txt');
    final (stil, bugs) = await Isolate.run(
      () => (_readFile(stilPath), _readFile(bugPath)),
    );
    if (stil.isEmpty) return null;
    return StilDatabase._(stilPath, p.dirname(docs), stil, bugs);
  }

  /// Synchronous version of [load] (tests, isolates).
  static StilDatabase? loadSync(String stilPath) {
    final docs = p.dirname(stilPath);
    final stil = _readFile(stilPath);
    if (stil.isEmpty) return null;
    return StilDatabase._(
      stilPath,
      p.dirname(docs),
      stil,
      _readFile(p.join(docs, 'BUGlist.txt')),
    );
  }

  static Map<String, String> _readFile(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return {};
      return parseEntries(latin1.decode(f.readAsBytesSync()));
    } catch (_) {
      return {};
    }
  }

  /// Splits STIL/BUGlist text into HVSC path (lower case) -> entry text.
  static Map<String, String> parseEntries(String text) {
    final out = <String, String>{};
    String? path;
    final body = StringBuffer();
    void flush() {
      if (path != null) out[path!.toLowerCase()] = body.toString();
      path = null;
      body.clear();
    }

    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith('#')) continue;
      if (line.startsWith('/')) {
        flush();
        path = line.trim();
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      if (path != null) body.writeln(line);
    }
    flush();
    return out;
  }

  /// The HVSC path of [file] ("/MUSICIANS/H/Hubbard_Rob/Commando.sid"), or
  /// null if it does not look like a file from HVSC.
  String? hvscPath(String file) {
    String? rel;
    if (p.isWithin(root, file)) {
      rel = p.relative(file, from: root);
    } else {
      // A copy of HVSC somewhere else: find a top-level HVSC folder name.
      final parts = p.split(file);
      final i = parts.lastIndexWhere(
        (s) => const {'MUSICIANS', 'GAMES', 'DEMOS'}.contains(s.toUpperCase()),
      );
      if (i < 0) return null;
      rel = p.joinAll(parts.sublist(i));
    }
    return '/${p.split(rel).join('/')}';
  }

  /// Everything STIL and BUGlist know about [file].
  TuneStil lookup(String file) {
    final hp = hvscPath(file);
    if (hp == null) return const TuneStil();
    final key = hp.toLowerCase();
    StilEntry? entry(Map<String, String> m, String k, String path) {
      final raw = m[k];
      return raw == null ? null : StilEntry.parse(path, raw);
    }

    final folders = <StilEntry>[];
    var dir = hp.substring(0, hp.lastIndexOf('/'));
    while (dir.isNotEmpty) {
      final e = entry(_stil, '${dir.toLowerCase()}/', '$dir/');
      if (e != null && !e.isEmpty) folders.add(e);
      dir = dir.substring(0, dir.lastIndexOf('/'));
    }
    return TuneStil(
      tune: entry(_stil, key, hp),
      folders: folders,
      bugs: entry(_bugs, key, hp),
    );
  }

  /// Finds STIL.txt in an HVSC DOCUMENTS folder near [dir] (an HVSC root,
  /// its parent, or a folder inside it), or null.
  static String? find(String dir) {
    final candidates = [
      p.join(dir, 'DOCUMENTS', 'STIL.txt'),
      p.join(dir, 'C64Music', 'DOCUMENTS', 'STIL.txt'),
      p.join(p.dirname(dir), 'DOCUMENTS', 'STIL.txt'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}
