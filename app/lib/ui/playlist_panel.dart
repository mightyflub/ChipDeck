// Playlist: searchable list of tunes with add/remove.
import 'package:flutter/material.dart';

import '../player/player_controller.dart';
import 'theme.dart';

class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({
    super.key,
    required this.controller,
    required this.onAddFiles,
    required this.onAddFolder,
    this.onPlayed,
  });

  final PlayerController controller;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback? onPlayed;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ColoredBox(
      color: Palette.panel,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final q = _query.toLowerCase();
          final indices = <int>[
            for (var i = 0; i < c.playlist.length; i++)
              if (q.isEmpty ||
                  c.playlist[i].title.toLowerCase().contains(q) ||
                  c.playlist[i].author.toLowerCase().contains(q) ||
                  c.playlist[i].fileName.toLowerCase().contains(q))
                i,
          ];
          return LayoutBuilder(
            builder: (context, box) {
              // Short screens: title, search and actions share one row.
              final compact = box.maxHeight < 480;
              // Wide enough for one line per tune.
              final dense = box.maxWidth >= 560;
              final showSearch = c.playlist.isNotEmpty;
              return Column(
                children: [
                  Padding(
                    padding: compact
                        ? const EdgeInsets.fromLTRB(8, 6, 4, 6)
                        : const EdgeInsets.fromLTRB(16, 14, 8, 6),
                    child: Row(
                      children: [
                        if (compact && showSearch)
                          Expanded(child: _searchField())
                        else
                          Text(
                            'Playlist',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        const SizedBox(width: 8),
                        if (c.playlist.isNotEmpty)
                          _Badge(text: '${c.playlist.length}'),
                        if (!(compact && showSearch)) const Spacer(),
                        IconButton(
                          tooltip: c.shuffle ? 'Shuffle on' : 'Shuffle off',
                          isSelected: c.shuffle,
                          icon: const Icon(Icons.shuffle),
                          selectedIcon: const Icon(
                            Icons.shuffle_on_outlined,
                            color: Palette.accent,
                          ),
                          onPressed: c.toggleShuffle,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Playlist actions',
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) {
                            if (v == 'files') widget.onAddFiles();
                            if (v == 'folder') widget.onAddFolder();
                            if (v == 'clear') c.clearPlaylist();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'files',
                              child: Text('Add files…'),
                            ),
                            PopupMenuItem(
                              value: 'folder',
                              child: Text('Add folder…'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'clear',
                              child: Text('Clear playlist'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showSearch && !compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _searchField(),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: c.playlist.isEmpty
                        ? _EmptyState(
                            onAddFiles: widget.onAddFiles,
                            onAddFolder: widget.onAddFolder,
                          )
                        : Scrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              itemCount: indices.length,
                              itemExtent: dense ? 40 : 56,
                              itemBuilder: (context, row) {
                                final i = indices[row];
                                return _PlaylistRow(
                                  dense: dense,
                                  index: i,
                                  entry: c.playlist[i],
                                  isCurrent: i == c.currentIndex,
                                  isPlaying: i == c.currentIndex && c.playing,
                                  onTap: () {
                                    c.playIndex(i);
                                    widget.onPlayed?.call();
                                  },
                                  onRemove: () => c.removeAt(i),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search title, author or file',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
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
}

class _PlaylistRow extends StatefulWidget {
  const _PlaylistRow({
    required this.index,
    required this.entry,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onRemove,
    this.dense = false,
  });

  /// One line: number, title, author, subtunes (wide lists).
  final bool dense;
  final int index;
  final PlaylistEntry entry;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends State<_PlaylistRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final subs = e.info?.subtunes ?? 0;
    final dim = e.failed ? 0.45 : 1.0;
    final titleColor = widget.isCurrent ? Palette.accent : Colors.white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.isCurrent
            ? Palette.accent.withValues(alpha: 0.12)
            : (_hover ? Palette.panelHigh : Colors.transparent),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onRemove,
          child: Opacity(
            opacity: dim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: widget.isPlaying
                        ? const Icon(
                            Icons.graphic_eq,
                            size: 18,
                            color: Palette.accent,
                          )
                        : Text(
                            '${widget.index + 1}',
                            style: const TextStyle(
                              color: Palette.textMuted,
                              fontSize: 12,
                              fontFeatures: tabular,
                            ),
                          ),
                  ),
                  if (widget.dense) ...[
                    Expanded(
                      flex: 5,
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: widget.isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(
                        e.failed
                            ? 'Cannot read ${e.fileName}'
                            : (e.author.isEmpty ? e.fileName : e.author),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: widget.isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.failed
                                ? 'Cannot read ${e.fileName}'
                                : (e.author.isEmpty ? e.fileName : e.author),
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
                  if (_hover)
                    IconButton(
                      tooltip: 'Remove from playlist',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Palette.textMuted,
                      ),
                      onPressed: widget.onRemove,
                    )
                  else if (subs > 1)
                    _Badge(text: '$subs', tooltip: '$subs subtunes'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.tooltip});
  final String text;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.panelHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Palette.textMuted,
          fontFeatures: tabular,
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFiles, required this.onAddFolder});
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 48,
              color: Palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No tunes yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Add .sid, .sndh or .ym files, or a whole folder such as your HVSC collection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.textMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAddFiles,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add files'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
