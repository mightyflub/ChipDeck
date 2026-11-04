// Main window: playlist + now playing, adapting to narrow (phone) widths.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/player_controller.dart';
import 'now_playing.dart';
import 'playlist_panel.dart';
import 'settings_dialog.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0; // narrow layout: 0 = now playing, 1 = playlist

  PlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final msg = c.message;
    if (msg != null) {
      c.message = null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> pickFiles() async {
    const group = XTypeGroup(
      label: 'SID tunes',
      extensions: ['sid', 'psid', 'rsid', 'mus', 'prg'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;
    final start = c.playlist.length;
    c.addFiles(files.map((f) => f.path).toList());
    if (c.current == null && c.playlist.length > start) c.playIndex(start);
  }

  Future<void> pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    final start = c.playlist.length;
    final n = await c.addFolder(dir);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? 'No SID files found in that folder.' : 'Added $n tunes.')));
    if (c.current == null && n > 0) c.playIndex(start);
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx?.widget is EditableText;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_typing()) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      c.togglePlay();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.nextSubtune();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      c.previousSubtune();
    } else if (k == LogicalKeyboardKey.keyN || k == LogicalKeyboardKey.pageDown) {
      c.nextTrack();
    } else if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.pageUp) {
      c.previousTrack();
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadAdd) {
      c.setVolume((c.volume + 0.05).clamp(0, 1));
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      c.setVolume((c.volume - 0.05).clamp(0, 1));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final playlist = PlaylistPanel(
          controller: c,
          onAddFiles: pickFiles,
          onAddFolder: pickFolder,
          onPlayed: wide ? null : () => setState(() => _tab = 0),
        );
        final nowPlaying = NowPlaying(controller: c, compact: !wide);
        return Scaffold(
          appBar: _appBar(context),
          body: c.hasEngine
              ? (wide
                  ? Row(children: [
                      SizedBox(width: (box.maxWidth * 0.36).clamp(320, 460), child: playlist),
                      const VerticalDivider(width: 1),
                      Expanded(child: nowPlaying),
                    ])
                  : IndexedStack(index: _tab, children: [nowPlaying, playlist]))
              : _EngineError(message: c.engineError ?? 'Unknown error'),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  backgroundColor: Palette.panel,
                  indicatorColor: Palette.accent.withValues(alpha: 0.25),
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Now playing'),
                    NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
                  ],
                ),
        );
      }),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      title: Row(children: [
        const _Logo(),
        const SizedBox(width: 10),
        Text('ChipDeck',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),
      actions: [
        IconButton(
          tooltip: 'Add files',
          icon: const Icon(Icons.note_add_outlined),
          onPressed: c.hasEngine ? pickFiles : null,
        ),
        IconButton(
          tooltip: 'Add folder',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: c.hasEngine ? pickFolder : null,
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.tune),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => SettingsDialog(controller: c),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    // Four rainbow stripes, a nod to the C64 badge.
    const colors = [Color(0xFFFF5F6D), Color(0xFFFFB86B), Color(0xFF7CE38B), Color(0xFF5CE1E6)];
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Palette.panelHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final col in colors)
            Container(height: 2.2, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(1))),
        ],
      ),
    );
  }
}

class _EngineError extends StatelessWidget {
  const _EngineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.speaker_notes_off_outlined, size: 48, color: Palette.warm),
          const SizedBox(height: 16),
          Text('Audio engine unavailable', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textMuted)),
        ]),
      ),
    );
  }
}
