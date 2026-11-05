// Library: saved archive locations, folder browser and search.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library.dart';
import '../platform/files.dart' as files;
import '../player/player_controller.dart';
import 'format_filter.dart';
import 'theme.dart';

class LibraryPanel extends StatefulWidget {
  const LibraryPanel({
    super.key,
    required this.library,
    required this.player,
    this.onPlayed,
  });

  final LibraryController library;
  final PlayerController player;
  final VoidCallback? onPlayed;

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  FormatFilter _filter = FormatFilter.all;
  static const _filterPref = 'libraryFormats';
  String? _dir; // current folder in browse mode; null = locations
  Timer? _debounce;
  List<LibraryTrack> _results = const [];
  Object? _resultsKey; // (query, filter, track list) the results were made for

  LibraryController get lib => widget.library;
  PlayerController get player => widget.player;

  @override
  void initState() {
    super.initState();
    // The format filter is remembered between runs.
    SharedPreferences.getInstance().then((prefs) {
      final saved = FormatFilter.fromJson(prefs.getStringList(_filterPref));
      if (mounted && saved != _filter) setState(() => _filter = saved);
    });
  }

  void _setFilter(FormatFilter f) {
    _filter = f;
    _runSearch();
    SharedPreferences.getInstance().then(
      (prefs) => f.isAll
          ? prefs.remove(_filterPref)
          : prefs.setStringList(_filterPref, f.toJson()),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _runSearch() => setState(() {});

  List<LibraryTrack> _currentResults() {
    final key = (
      _query.trim(),
      _filter,
      identityHashCode(lib.tracks),
      lib.tracks.length,
    );
    if (key != _resultsKey) {
      _results = lib.search(_query, filter: _filter);
      _resultsKey = key;
    }
    return _results;
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      _query = v;
      _runSearch();
    });
  }

  void _open(String dir) {
    setState(() => _dir = dir);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Plays [list][index] without adding anything to the playlist; next and
  /// previous carry on through [list] (the folder or the search results).
  void _playTrack(List<LibraryTrack> list, int index) {
    player.playFromLibrary([
      for (final t in list) (t.path, t.toInfo()),
    ], start: index);
    widget.onPlayed?.call();
  }

  void _addTrack(LibraryTrack t) {
    player.addKnown([(t.path, t.toInfo())]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${t.displayTitle}" to the playlist.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// [replace]: play the tunes straight from the library (the playlist is
  /// left alone); otherwise add them to the playlist.
  void _playMany(List<LibraryTrack> ts, {required bool replace}) {
    if (ts.isEmpty) return;
    if (replace) {
      _playTrack(ts, 0);
      return;
    }
    player.addKnown([for (final t in ts) (t.path, t.toInfo())]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${ts.length} tunes to the playlist.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addLocation() async {
    final dir = await files.pickFolder(
      context,
      confirmButtonText: 'Add to library',
    );
    if (dir != null) await lib.addRoot(dir);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.panel,
      child: ListenableBuilder(
        listenable: Listenable.merge([lib, player]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final searching = _query.trim().isNotEmpty || !_filter.isAll;
            // Short screens (phones and handhelds in landscape): one toolbar
            // row instead of header + search box + filter chips + results
            // header, so most of the height goes to the list.
            final compact = box.maxHeight < 480;
            // Wide enough for one line per tune (title, composer, year...).
            final dense = box.maxWidth >= 560;
            final results = searching ? _currentResults() : null;
            return Column(
              children: [
                if (compact && lib.roots.isNotEmpty)
                  _compactBar(context, results)
                else ...[
                  _header(context),
                  if (lib.roots.isNotEmpty) _searchBox(),
                ],
                if (lib.scan != null) _ScanBar(scan: lib.scan!),
                const Divider(height: 1),
                Expanded(
                  child: lib.roots.isEmpty
                      ? _NoLocations(onAdd: _addLocation)
                      : results != null
                      ? _resultsList(results, header: !compact, dense: dense)
                      : _browser(dense: dense),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Text(
            '${lib.tracks.length} tunes',
            style: const TextStyle(
              color: Palette.textMuted,
              fontFeatures: tabular,
            ),
          ),
          const Spacer(),
          _RefreshButton(library: lib),
          IconButton(
            tooltip: 'Music locations',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _LocationsDialog(library: lib, onAdd: _addLocation),
            ),
            icon: const Icon(Icons.folder_special_outlined),
          ),
        ],
      ),
    );
  }

  Widget _searchField({required String hint}) {
    return TextField(
      controller: _search,
      onChanged: _onQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _search.clear();
                  _onQuery('');
                },
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

  /// Everything on one row: search, format filter, match count and actions.
  Widget _compactBar(BuildContext context, List<LibraryTrack>? results) {
    const muted = TextStyle(
      color: Palette.textMuted,
      fontSize: 12,
      fontFeatures: tabular,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: _searchField(hint: 'Search ${lib.tracks.length} tunes'),
          ),
          const SizedBox(width: 6),
          FormatFilterButton(
            filter: _filter,
            counts: lib.formatCounts,
            onChanged: _setFilter,
            dense: true,
          ),
          if (results != null) ...[
            const SizedBox(width: 8),
            Text(
              results.length >= 1000 ? '1000+' : '${results.length}',
              style: muted,
            ),
            IconButton(
              tooltip: 'Play all matches',
              visualDensity: VisualDensity.compact,
              onPressed: results.isEmpty
                  ? null
                  : () => _playMany(results, replace: true),
              icon: const Icon(Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Add all matches to playlist',
              visualDensity: VisualDensity.compact,
              onPressed: results.isEmpty
                  ? null
                  : () => _playMany(results, replace: false),
              icon: const Icon(Icons.playlist_add, size: 20),
            ),
          ] else ...[
            _RefreshButton(library: lib, compact: true),
            IconButton(
              tooltip: 'Music locations',
              visualDensity: VisualDensity.compact,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    _LocationsDialog(library: lib, onAdd: _addLocation),
              ),
              icon: const Icon(Icons.folder_special_outlined, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(child: _searchField(hint: 'Search tunes')),
          const SizedBox(width: 8),
          FormatFilterButton(
            filter: _filter,
            counts: lib.formatCounts,
            onChanged: _setFilter,
          ),
        ],
      ),
    );
  }

  Widget _resultsList(
    List<LibraryTrack> r, {
    required bool header,
    required bool dense,
  }) {
    if (r.isEmpty) {
      return const Center(
        child: Text('No matches.', style: TextStyle(color: Palette.textMuted)),
      );
    }
    return Column(
      children: [
        if (header)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  r.length >= 1000
                      ? 'First 1000 matches'
                      : '${r.length} matches',
                  style: const TextStyle(
                    color: Palette.textMuted,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _playMany(r, replace: true),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play all'),
                ),
                IconButton(
                  tooltip: 'Add all to playlist',
                  onPressed: () => _playMany(r, replace: false),
                  icon: const Icon(Icons.playlist_add, size: 20),
                ),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              itemCount: r.length,
              itemExtent: dense ? _TrackRow.denseExtent : 56,
              itemBuilder: (context, i) => _TrackRow(
                track: r[i],
                showFolder: true,
                dense: dense,
                isCurrent: player.current?.path == r[i].path,
                onPlay: () => _playTrack(r, i),
                onAdd: () => _addTrack(r[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _browser({required bool dense}) {
    final dir = _dir;
    final folder = dir == null ? null : lib.folder(dir);
    if (dir != null && folder == null) {
      // Folder vanished after a rescan.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _dir = null),
      );
    }
    final root = dir == null
        ? null
        : lib.roots.firstWhere(
            (r) => p.equals(r, dir) || p.isWithin(r, dir),
            orElse: () => '',
          );
    final children = folder?.children ?? lib.roots;
    final trackIdx = folder?.tracks ?? const <int>[];
    return Column(
      children: [
        if (dir != null)
          _Breadcrumb(
            root: root!,
            dir: dir,
            onOpen: _open,
            onHome: () => setState(() => _dir = null),
            onPlayAll: () => _playMany(lib.tracksUnder(dir), replace: true),
            onAddAll: () => _playMany(lib.tracksUnder(dir), replace: false),
            total: folder?.totalTracks ?? 0,
          ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              itemCount: children.length + trackIdx.length,
              itemExtent: dense ? 44 : 52,
              itemBuilder: (context, i) {
                if (i < children.length) {
                  final c = children[i];
                  final f = lib.folder(c);
                  return _FolderRow(
                    name: p.basename(c).isEmpty ? c : p.basename(c),
                    subtitle: dir == null ? p.dirname(c) : null,
                    isRoot: dir == null,
                    count: f?.totalTracks ?? 0,
                    onOpen: () => _open(c),
                    onPlay: () => _playMany(lib.tracksUnder(c), replace: true),
                  );
                }
                final t = lib.tracks[trackIdx[i - children.length]];
                return _TrackRow(
                  track: t,
                  showFolder: false,
                  dense: dense,
                  isCurrent: player.current?.path == t.path,
                  onPlay: () => _playTrack([
                    for (final j in trackIdx) lib.tracks[j],
                  ], i - children.length),
                  onAdd: () => _addTrack(t),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanBar extends StatelessWidget {
  const _ScanBar({required this.scan});
  final ScanProgress scan;

  @override
  Widget build(BuildContext context) {
    final frac = scan.total == 0 ? null : scan.done / scan.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scan.total == 0
                ? scan.phase
                : '${scan.phase} ${scan.done} of ${scan.total}…',
            style: const TextStyle(
              fontSize: 12,
              color: Palette.textMuted,
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor: Palette.panelHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.root,
    required this.dir,
    required this.onOpen,
    required this.onHome,
    required this.onPlayAll,
    required this.onAddAll,
    required this.total,
  });

  final String root;
  final String dir;
  final ValueChanged<String> onOpen;
  final VoidCallback onHome;
  final VoidCallback onPlayAll;
  final VoidCallback onAddAll;
  final int total;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[root];
    if (!p.equals(root, dir)) {
      var d = dir;
      final stack = <String>[];
      while (!p.equals(d, root)) {
        stack.add(d);
        d = p.dirname(d);
      }
      parts.addAll(stack.reversed);
    }
    final parent = p.equals(root, dir) ? null : p.dirname(dir);
    return Container(
      color: Palette.panelHigh,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Up',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: parent == null ? onHome : () => onOpen(parent),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // keep the deepest folder visible
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: onHome,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.home_outlined,
                            size: 18,
                            color: Palette.textMuted,
                          ),
                        ),
                      ),
                      for (var i = 0; i < parts.length; i++) ...[
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Palette.textMuted,
                        ),
                        InkWell(
                          onTap: () => onOpen(parts[i]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              i == 0
                                  ? _rootLabel(parts[i])
                                  : p.basename(parts[i]),
                              style: TextStyle(
                                fontSize: 13,
                                color: i == parts.length - 1
                                    ? Colors.white
                                    : Palette.textMuted,
                                fontWeight: i == parts.length - 1
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Play all $total tunes here (replaces playlist)',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.play_circle_outline, size: 20),
              onPressed: total == 0 ? null : onPlayAll,
            ),
          ),
          Tooltip(
            message: 'Add all $total tunes here to the playlist',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.playlist_add, size: 20),
              onPressed: total == 0 ? null : onAddAll,
            ),
          ),
        ],
      ),
    );
  }

  static String _rootLabel(String r) {
    final b = p.basename(r);
    return b.isEmpty ? r : b;
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    this.subtitle,
    required this.isRoot,
    required this.count,
    required this.onOpen,
    required this.onPlay,
  });

  final String name;
  final String? subtitle;
  final bool isRoot;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              isRoot ? Icons.storage_rounded : Icons.folder_rounded,
              size: 20,
              color: isRoot
                  ? Palette.scope
                  : Palette.warm.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRoot ? name : name.replaceAll('_', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 12,
                fontFeatures: tabular,
              ),
            ),
            IconButton(
              tooltip: 'Play folder',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: Palette.textMuted,
              ),
              onPressed: count == 0 ? null : onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.showFolder,
    required this.isCurrent,
    required this.onPlay,
    required this.onAdd,
    this.dense = false,
  });

  /// Row height for the one-line layout.
  static const double denseExtent = 40;

  final LibraryTrack track;
  final bool showFolder;

  /// One line per tune with columns (wide lists), instead of two lines.
  final bool dense;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (dense) return _buildDense(context);
    final t = track;
    final sub = [
      if (t.author.isNotEmpty) t.author,
      if (t.released.isNotEmpty) t.released,
      if (showFolder) _folderLabel(t),
    ].where((x) => x.isNotEmpty).join(' · ');
    return Material(
      color: isCurrent
          ? Palette.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  t.kind,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: systemColor(t.system),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? Palette.accent : Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (t.lengthMs > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    formatMs(t.lengthMs),
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              if (t.subtunes > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: '${t.subtunes} subtunes',
                    child: Text(
                      '×${t.subtunes}',
                      style: const TextStyle(
                        color: Palette.textMuted,
                        fontSize: 12,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Add to playlist',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.playlist_add,
                  size: 20,
                  color: Palette.textMuted,
                ),
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _TrackRow {
  Widget _buildDense(BuildContext context) {
    final t = track;
    const muted = TextStyle(color: Palette.textMuted, fontSize: 12);
    const num = TextStyle(
      color: Palette.textMuted,
      fontSize: 12,
      fontFeatures: tabular,
    );
    final folder = showFolder ? _folderLabel(t) : '';
    return Material(
      color: isCurrent
          ? Palette.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  t.kind,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: systemColor(t.system),
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  t.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? Palette.accent : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  t.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(_year(t.released), maxLines: 1, style: num),
              ),
              if (showFolder) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ],
              SizedBox(
                width: 44,
                child: Text(
                  t.lengthMs > 0 ? formatMs(t.lengthMs) : '',
                  textAlign: TextAlign.right,
                  style: num,
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  t.subtunes > 1 ? '×${t.subtunes}' : '',
                  textAlign: TextAlign.right,
                  style: num,
                ),
              ),
              IconButton(
                tooltip: 'Add to playlist',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.playlist_add,
                  size: 20,
                  color: Palette.textMuted,
                ),
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The year from a "released" string like "1987 Hubbard" (else the start).
String _year(String released) {
  final m = RegExp(r'(19|20)\d\d').firstMatch(released);
  if (m != null) return m.group(0)!;
  return released.length <= 4 ? released : released.substring(0, 4);
}

/// Folder name for search results, skipped when it just repeats the author
/// (HVSC folders are named after the composer).
String _folderLabel(LibraryTrack t) {
  final f = p.basename(p.dirname(t.path)).replaceAll('_', ' ');
  if (t.author.isNotEmpty &&
      f.toLowerCase().startsWith(t.author.toLowerCase())) {
    return '';
  }
  return f;
}

class _NoLocations extends StatelessWidget {
  const _NoLocations({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storage_rounded,
              size: 48,
              color: Palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Add your music archive',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Point ChipDeck at the folders where you keep your tunes, such as HVSC (C64Music) or the SNDH archive. '
              'It indexes them so you can browse and search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add location'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationsDialog extends StatelessWidget {
  const _LocationsDialog({required this.library, required this.onAdd});
  final LibraryController library;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => AlertDialog(
        backgroundColor: Palette.panel,
        title: const Text('Music locations'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (library.roots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No locations yet.',
                    style: TextStyle(color: Palette.textMuted),
                  ),
                ),
              for (final r in library.roots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.storage_rounded,
                    color: Palette.scope,
                  ),
                  title: Text(r, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    library.scanningRoots.contains(r)
                        ? 'Refreshing…'
                        : '${library.folder(r)?.totalTracks ?? 0} tunes'
                              '${library.rootScans[r] == null ? '' : ' · refreshed ${_fmt(library.rootScans[r]!)}'}',
                    style: const TextStyle(color: Palette.textMuted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Refresh this location',
                        icon: const Icon(Icons.refresh),
                        onPressed: library.isScanning
                            ? null
                            : () => library.rescan(only: [r]),
                      ),
                      IconButton(
                        tooltip: 'Remove from library (files are not deleted)',
                        icon: const Icon(Icons.close),
                        onPressed: () => library.removeRoot(r),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (library.lastScan != null)
                Text(
                  'Last refresh: ${_fmt(library.lastScan!)}',
                  style: const TextStyle(
                    color: Palette.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: library.isScanning || library.roots.isEmpty
                ? null
                : () => library.rescan(full: true),
            child: const Text('Rebuild index'),
          ),
          TextButton(
            onPressed: library.isScanning || library.roots.isEmpty
                ? null
                : () => library.rescan(),
            child: const Text('Refresh all'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAdd(),
            icon: const Icon(Icons.add),
            label: const Text('Add location'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Refresh menu: every location at once, or one of them. With a single
/// location it is a plain button.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.library, this.compact = false});
  final LibraryController library;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.refresh, size: compact ? 20 : null);
    final density = compact ? VisualDensity.compact : null;
    final disabled = library.isScanning || library.roots.isEmpty;
    if (library.roots.length < 2) {
      return IconButton(
        tooltip: 'Refresh library',
        visualDensity: density,
        onPressed: disabled ? null : () => library.rescan(),
        icon: icon,
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Refresh library',
      enabled: !disabled,
      icon: icon,
      style: density == null
          ? null
          : IconButton.styleFrom(visualDensity: density),
      // '' means every location (a null value would count as cancelled).
      onSelected: (r) => library.rescan(only: r.isEmpty ? null : [r]),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: '',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh),
            title: Text('Refresh all locations'),
          ),
        ),
        const PopupMenuDivider(),
        for (final r in library.roots)
          PopupMenuItem<String>(
            value: r,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storage_rounded),
              title: Text(
                p.basename(r).isEmpty ? r : p.basename(r),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                r,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}
