// Main window: library, now playing and playlists, adapting to narrow (phone) widths.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library.dart';
import '../platform/second_screen.dart';
import '../platform/files.dart' as files;
import '../player/player_controller.dart';
import 'library_panel.dart';
import 'now_playing.dart';
import 'playlist_panel.dart';
import 'settings_dialog.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, required this.library});

  final PlayerController controller;
  final LibraryController library;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0; // narrow layout: 0 = now playing, 1 = library, 2 = playlist
  int _side = 0; // wide layout side panel: 0 = library, 1 = playlist

  PlayerController get c => widget.controller;
  LibraryController get lib => widget.library;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    lib.addListener(_onChange);
    // Start in the library when the user has one, else in the playlist.
    _side = lib.roots.isEmpty && c.playlist.isNotEmpty ? 1 : 0;
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    lib.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final fromLib = c.message == null && lib.message != null;
    final msg = c.message ?? lib.message;
    if (msg != null) {
      final report = fromLib && lib.messageHasIssues;
      c.message = null;
      lib.message = null;
      lib.messageHasIssues = false;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: Duration(seconds: report ? 10 : 4),
            action: report
                ? SnackBarAction(
                    label: 'Details',
                    onPressed: () => showScanReport(context, lib),
                  )
                : null,
          ),
        );
    }
  }

  Future<void> pickFiles() async {
    final paths = await files.pickTuneFiles(context);
    if (paths.isEmpty) return;
    final start = c.playlist.length;
    c.addFiles(paths);
    if (c.current == null && c.playlist.length > start) c.playIndex(start);
  }

  Future<void> pickFolder() async {
    final dir = await files.pickFolder(context);
    if (dir == null) return;
    final start = c.playlist.length;
    final n = await c.addFolder(dir);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'No supported tunes found in that folder.'
              : 'Added $n tunes.',
        ),
      ),
    );
    if (c.current == null && n > 0) c.playIndex(start);
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
            ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx?.widget is EditableText;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_typing()) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    // Keys 1-9 mute/unmute channels 1-9, 0 unmutes all (0.12.0).
    const digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final digit = digits.indexOf(k);
    if (digit == 0 && e is KeyDownEvent) {
      c.unmuteAll();
    } else if (digit > 0 && e is KeyDownEvent) {
      c.toggleMute(digit - 1);
    } else if (shift && k == LogicalKeyboardKey.arrowRight) {
      c.seekBy(10000); // Shift+Right/Left: jump 10 s (0.12.0)
    } else if (shift && k == LogicalKeyboardKey.arrowLeft) {
      c.seekBy(-10000);
    } else if (k == LogicalKeyboardKey.space) {
      c.togglePlay();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.nextSubtune();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      c.previousSubtune();
    } else if (k == LogicalKeyboardKey.keyN ||
        k == LogicalKeyboardKey.pageDown) {
      c.nextTrack();
    } else if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.pageUp) {
      c.previousTrack();
    } else if (k == LogicalKeyboardKey.keyF) {
      c.toggleFavourite();
    } else if (k == LogicalKeyboardKey.keyS) {
      c.toggleShuffle();
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.numpadAdd) {
      c.setVolume((c.volume + 0.05).clamp(0, 1));
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
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
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 860;
          // Phone back button: return to Now playing first.
          return PopScope(
            canPop: wide || _tab == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _tab = 0);
            },
            child: _body(context, box, wide),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, BoxConstraints box, bool wide) {
    final playlist = PlaylistPanel(
      controller: c,
      onAddFiles: pickFiles,
      onAddFolder: pickFolder,
      onPlayed: wide ? null : () => setState(() => _tab = 0),
    );
    final library = LibraryPanel(
      library: lib,
      player: c,
      onPlayed: wide ? null : () => setState(() => _tab = 0),
    );
    final nowPlaying = NowPlaying(controller: c, compact: !wide);
    // Short screens (phones and handhelds in landscape): a side rail
    // replaces the title bar and the bottom bar, leaving the height for
    // lists.
    final short = !wide && box.maxHeight < 560;
    // Room for three columns (the Windows window opens at 1280 wide).
    final xwide = wide && box.maxWidth >= 1200;
    final content = c.hasEngine
        ? (xwide
              // Large windows: library, now playing and playlist side by
              // side, so nothing hides behind a switch.
              ? Row(
                  children: [
                    SizedBox(
                      width: (box.maxWidth * 0.3).clamp(360, 560),
                      child: library,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: nowPlaying),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: (box.maxWidth * 0.22).clamp(290, 420),
                      child: playlist,
                    ),
                  ],
                )
              : wide
              ? Row(
                  children: [
                    SizedBox(
                      width: (box.maxWidth * 0.38).clamp(340, 520),
                      child: _SidePanel(
                        index: _side,
                        onChanged: (i) => setState(() => _side = i),
                        library: library,
                        playlist: playlist,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: nowPlaying),
                  ],
                )
              : IndexedStack(
                  index: _tab,
                  children: [nowPlaying, library, playlist],
                ))
        : _EngineError(message: c.engineError ?? 'Unknown error');
    return Scaffold(
      appBar: short ? null : _appBar(context),
      body: short
          ? SafeArea(
              child: Row(
                children: [
                  _rail(),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            )
          : content,
      bottomNavigationBar: wide || short
          ? null
          : NavigationBar(
              backgroundColor: Palette.panel,
              indicatorColor: Palette.accent.withValues(alpha: 0.25),
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.graphic_eq),
                  label: 'Now playing',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music),
                  label: 'Playlists',
                ),
              ],
            ),
    );
  }

  Widget _rail() {
    // Rebuilds with the player so the play/pause button stays current.
    return ListenableBuilder(
      listenable: Listenable.merge([c, secondScreenActive]),
      builder: (context, _) => _railBody(),
    );
  }

  Widget _raiseControlsButton() => IconButton(
    tooltip: 'Show the controls on the second screen',
    icon: const Icon(Icons.splitscreen),
    onPressed: raiseSecondScreen,
  );

  Widget _railBody() {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              backgroundColor: Palette.panel,
              indicatorColor: Palette.accent.withValues(alpha: 0.25),
              minWidth: 60,
              labelType: NavigationRailLabelType.none,
              groupAlignment: -0.6,
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              leading: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: _Logo(),
              ),
              // Play/pause and next stay reachable from every tab.
              trailing: Column(
                children: [
                  const SizedBox(height: 8),
                  if (secondScreenActive.value) _raiseControlsButton(),
                  if (!secondScreenActive.value) ...[
                    IconButton(
                      tooltip: c.playing ? 'Pause' : 'Play',
                      color: Palette.accent,
                      onPressed: c.current != null || c.playlist.isNotEmpty
                          ? c.togglePlay
                          : null,
                      icon: Icon(
                        c.playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 32,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next tune',
                      onPressed: c.canSkip ? c.nextTrack : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      switch (v) {
                        case 'files':
                          pickFiles();
                        case 'folder':
                          pickFolder();
                        case 'settings':
                          showDialog<void>(
                            context: context,
                            builder: (_) => SettingsDialog(controller: c),
                          );
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'files',
                        enabled: c.hasEngine,
                        child: const Text('Add files'),
                      ),
                      PopupMenuItem(
                        value: 'folder',
                        enabled: c.hasEngine,
                        child: const Text('Add folder'),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Settings'),
                      ),
                    ],
                  ),
                ],
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.graphic_eq),
                  label: Text('Now playing'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.library_music_outlined),
                  label: Text('Library'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.queue_music),
                  label: Text('Playlists'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      title: Row(
        children: [
          const _Logo(),
          const SizedBox(width: 10),
          Text(
            'ChipDeck',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: secondScreenActive,
          builder: (_, active, _) =>
              active ? _raiseControlsButton() : const SizedBox.shrink(),
        ),
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
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.index,
    required this.onChanged,
    required this.library,
    required this.playlist,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final Widget library;
  final Widget playlist;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.library_music_outlined, size: 18),
                    label: Text('Library'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: const Icon(Icons.queue_music, size: 18),
                    label: const Text('Playlists'),
                  ),
                ],
                selected: {index},
                onSelectionChanged: (s) => onChanged(s.first),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(index: index, children: [library, playlist]),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    // Four rainbow stripes, a nod to the C64 badge.
    const colors = [
      Color(0xFFFF5F6D),
      Color(0xFFFFB86B),
      Color(0xFF7CE38B),
      Color(0xFF5CE1E6),
    ];
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
            Container(
              height: 2.2,
              decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.speaker_notes_off_outlined,
              size: 48,
              color: Palette.warm,
            ),
            const SizedBox(height: 16),
            Text(
              'Audio engine unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
