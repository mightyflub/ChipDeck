// Player controls for a second screen (dual-screen handhelds such as the
// Ayn Thor). Runs in its own Flutter engine on the other display and only
// talks to the player through RemoteState and actions (see
// lib/platform/remote_controls.dart and SecondScreen.kt).
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native/chipdeck_ffi.dart' show TuneSystem;
import '../platform/remote_controls.dart';
import 'theme.dart';

class ControlsApp extends StatelessWidget {
  const ControlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChipDeck controls',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const ControlsScreen(),
    );
  }
}

class ControlsScreen extends StatefulWidget {
  const ControlsScreen({super.key});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  static const _channel = MethodChannel('chipdeck/controls');
  RemoteState _s = const RemoteState();

  /// Where the position bar is being dragged to (0..1).
  double? _drag;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && call.arguments is Map) {
        setState(() => _s = RemoteState.fromMap(call.arguments as Map));
      }
      return null;
    });
    // Ask the player for the current state.
    _channel.invokeMethod('ready');
  }

  void _send(String action, [Object? value]) {
    HapticFeedback.selectionClick();
    _channel.invokeMethod('action', {'action': action, 'value': value});
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (s.format.isNotEmpty)
                    _Tag(
                      s.system == TuneSystem.c64
                          ? _shortFormat(s.format)
                          : s.system.label.toUpperCase(),
                      color: systemColor(s.system),
                    ),
                  const Spacer(),
                  if (s.playlistLength > 0)
                    Text(
                      '${s.playlistIndex} / ${s.playlistLength}',
                      style: const TextStyle(
                        color: Palette.textMuted,
                        fontSize: 12,
                        fontFeatures: tabular,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                s.hasTune ? s.title : 'Nothing playing',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.hasTune
                    ? [
                        s.author,
                        s.released,
                      ].where((x) => x.isNotEmpty).join(' · ')
                    : 'Pick a tune on the other screen.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.hasTune ? Palette.accent : Palette.textMuted,
                ),
              ),
              const Spacer(),
              _progress(s),
              const Spacer(),
              _transport(s),
              const Spacer(),
              if (s.subtunes > 1) ...[_subtunes(s), const SizedBox(height: 12)],
              _bottomRow(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress(RemoteState s) {
    final len = s.lengthMs;
    final drag = _drag;
    final pos = drag != null && len != null
        ? (len * drag).round()
        : s.positionMs;
    final frac = len == null || len == 0 ? 0.0 : (pos / len).clamp(0.0, 1.0);
    const style = TextStyle(color: Palette.textMuted, fontFeatures: tabular);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: frac,
        minHeight: 6,
        backgroundColor: Palette.panelHigh,
        valueColor: const AlwaysStoppedAnimation(Palette.accent),
      ),
    );
    return Column(
      children: [
        if (!s.canSeek || len == null)
          bar
        else
          LayoutBuilder(
            builder: (context, box) {
              double at(double dx) =>
                  box.maxWidth <= 0 ? 0 : (dx / box.maxWidth).clamp(0.0, 1.0);
              void seek(double f) => _send('seek', (len * f).round());
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => seek(at(d.localPosition.dx)),
                onHorizontalDragStart: (d) =>
                    setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) =>
                    setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragEnd: (_) {
                  final f = _drag;
                  setState(() => _drag = null);
                  if (f != null) seek(f);
                },
                onHorizontalDragCancel: () => setState(() => _drag = null),
                child: SizedBox(
                  height: 24,
                  child: Align(alignment: Alignment.center, child: bar),
                ),
              );
            },
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(formatMs(pos), style: style),
            if (s.muted > 0) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _send('unmuteAll'),
                child: Text(
                  '${s.muted} muted · unmute',
                  style: const TextStyle(color: Palette.warm, fontSize: 12),
                ),
              ),
            ],
            const Spacer(),
            Text(
              len == null ? '∞' : '${s.lengthKnown ? '' : '~'}${formatMs(len)}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }

  Widget _transport(RemoteState s) {
    final active = s.hasTune || s.playlistLength > 0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 36,
            tooltip: 'Previous tune',
            onPressed: s.playlistLength > 0 ? () => _send('previous') : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton(
            iconSize: 32,
            tooltip: 'Previous subtune',
            onPressed: s.subtune > 1 ? () => _send('previousSubtune') : null,
            icon: const Icon(Icons.fast_rewind_rounded),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            iconSize: 48,
            style: IconButton.styleFrom(
              backgroundColor: Palette.accent,
              foregroundColor: Palette.background,
              minimumSize: const Size(84, 84),
            ),
            tooltip: s.playing ? 'Pause' : 'Play',
            onPressed: active ? () => _send('toggle') : null,
            icon: Icon(
              s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            iconSize: 32,
            tooltip: 'Next subtune',
            onPressed: s.subtune > 0 && s.subtune < s.subtunes
                ? () => _send('nextSubtune')
                : null,
            icon: const Icon(Icons.fast_forward_rounded),
          ),
          IconButton(
            iconSize: 36,
            tooltip: 'Next tune',
            onPressed: s.playlistLength > 0 ? () => _send('next') : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }

  Widget _subtunes(RemoteState s) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: s.subtunes,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, k) {
          final n = k + 1;
          final sel = n == s.subtune;
          return Material(
            color: sel ? Palette.accent : Palette.panelHigh,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _send('subtune', n),
              child: Container(
                width: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: n == s.startSubtune && !sel
                        ? Palette.accent.withValues(alpha: 0.6)
                        : Palette.border,
                  ),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                    color: sel ? Palette.background : Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _advanceIcons = [
    Icons.playlist_play,
    Icons.arrow_right_alt,
    Icons.repeat_one,
  ];
  static const _advanceLabels = [
    'All subtunes, then next tune',
    'Next tune when a song ends',
    'Repeat current subtune',
  ];

  Widget _bottomRow(RemoteState s) {
    final a = s.advance.clamp(0, _advanceIcons.length - 1);
    return Row(
      children: [
        IconButton(
          tooltip: _advanceLabels[a],
          onPressed: () => _send('advance', (a + 1) % _advanceIcons.length),
          icon: Icon(_advanceIcons[a], color: Palette.textMuted),
        ),
        IconButton(
          tooltip: s.shuffle ? 'Random order: on' : 'Random order: off',
          onPressed: () => _send('shuffle'),
          icon: Icon(
            Icons.shuffle,
            color: s.shuffle ? Palette.accent : Palette.textMuted,
          ),
        ),
        Expanded(
          child: Text(
            _advanceLabels[a],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Palette.textMuted, fontSize: 12),
          ),
        ),
        Icon(
          s.volume == 0 ? Icons.volume_off : Icons.volume_up,
          color: Palette.textMuted,
          size: 20,
        ),
        SizedBox(
          width: 140,
          child: Slider(
            value: s.volume.clamp(0.0, 1.0),
            onChanged: (v) {
              setState(
                () => _s = RemoteState.fromMap({...s.toMap(), 'volume': v}),
              );
              _send('volume', v);
            },
          ),
        ),
      ],
    );
  }

  static String _shortFormat(String f) {
    if (f.contains('RSID')) return 'RSID';
    if (f.contains('PSID')) return 'PSID';
    return f.length > 12 ? f.substring(0, 12) : f;
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = Palette.scope});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final col = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withValues(alpha: 0.5)),
        color: col.withValues(alpha: 0.08),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: col,
        ),
      ),
    );
  }
}
