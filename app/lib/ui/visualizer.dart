// Visualiser, redrawn every frame while playing. Two views (button in the
// corner, remembered): one oscilloscope per channel (SID voices + Digi,
// Atari YM A/B/C + STE DAC, one per tracker channel for MOD/XM), or the mixed
// output with SID voice tiles.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../player/player_controller.dart';
import 'theme.dart';

class Visualizer extends StatefulWidget {
  const Visualizer({super.key, required this.controller, this.height});
  final PlayerController controller;

  /// Scope height; null makes the scope fill the space left by the voice
  /// tiles (needs a bounded height, used by the landscape layout).
  final double? height;

  @override
  State<Visualizer> createState() => _VisualizerState();
}

class _VoiceState {
  double level = 0;
  String wave = '—';
  String note = '';
  bool gate = false;
}

/// Colour of a channel by name: SID voices 1-3 and YM A-C use the voice
/// colours, Digi/DAC/Samples the warm one.
Color channelColor(String name) {
  final n = name.contains(':') ? name.substring(name.indexOf(':') + 1) : name;
  switch (n) {
    case 'V1':
    case 'A':
      return Palette.voice[0];
    case 'V2':
    case 'B':
      return Palette.voice[1];
    case 'V3':
    case 'C':
      return Palette.voice[2];
    default:
      // Tracker channels ("1", "2", ...) cycle through four colours.
      final k = int.tryParse(n);
      if (k != null && k > 0) {
        return const [
          Color(0xFF8E7CFF),
          Color(0xFF5CE1E6),
          Color(0xFFFF7AB6),
          Palette.amiga,
        ][(k - 1) % 4];
      }
      return Palette.warm;
  }
}

class _VisualizerState extends State<Visualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Int16List _samples = Int16List(0);
  List<_VoiceState> _voices = List.generate(3, (_) => _VoiceState());

  // Per-channel view.
  List<String> _chanNames = const [];
  List<Int16List> _chans = const [];
  List<double> _peaks = const [];

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final c = widget.controller;
    if (!c.playing) {
      // Let meters fall to rest, then stop repainting.
      final busy =
          _voices.any((v) => v.level > 0.01) ||
          _samples.any((s) => s != 0) ||
          _chans.isNotEmpty;
      final names = c.channelNames;
      if (!busy && listEquals(names, _chanNames)) return;
      setState(() {
        for (final v in _voices) {
          v.level *= 0.85;
          v.gate = false;
        }
        _samples = Int16List(0);
        _chans = const [];
        _chanNames = names;
      });
      return;
    }
    if (c.showChannels) {
      _chanNames = c.channelNames;
      _chans = c.channelScopes(2048);
      if (_peaks.length != _chans.length) {
        _peaks = List.filled(_chans.length, 0.0);
      }
      for (var i = 0; i < _chans.length; i++) {
        var m = 0;
        for (final s in _chans[i]) {
          final a = s < 0 ? -s : s;
          if (a > m) m = a;
        }
        // Auto gain: follow peaks up at once, fall back slowly.
        _peaks[i] = math.max(m.toDouble(), _peaks[i] * 0.97);
      }
    } else if (_chans.isNotEmpty) {
      _chans = const [];
    }
    final sidChips = c.info?.sidChips ?? 1;
    if (sidChips == 0) {
      // Not a SID tune (Atari ST, modules): no register view, scope only.
      if (_voices.isNotEmpty) _voices = [];
      setState(() => _samples = c.showChannels ? _samples : c.scope(1536));
      return;
    }
    final chips = sidChips.clamp(1, 3);
    if (_voices.length != chips * 3) {
      _voices = List.generate(chips * 3, (_) => _VoiceState());
    }
    final clock = (c.info?.isNtsc ?? false) ? 1022727.0 : 985248.0;
    for (var chip = 0; chip < chips; chip++) {
      final regs = c.sidRegisters(chip);
      if (regs == null) continue;
      for (var v = 0; v < 3; v++) {
        _decodeVoice(regs, v, clock, _voices[chip * 3 + v]);
      }
    }
    setState(() => _samples = c.showChannels ? _samples : c.scope(1536));
  }

  static const _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  void _decodeVoice(Uint8List regs, int v, double clock, _VoiceState s) {
    final b = v * 7;
    final freq = regs[b] | (regs[b + 1] << 8);
    final ctrl = regs[b + 4];
    final sustain = (regs[b + 6] >> 4) / 15.0;
    s.gate = (ctrl & 1) != 0;
    final waves = <String>[
      if (ctrl & 0x10 != 0) 'TRI',
      if (ctrl & 0x20 != 0) 'SAW',
      if (ctrl & 0x40 != 0) 'PUL',
      if (ctrl & 0x80 != 0) 'NOI',
    ];
    s.wave = waves.isEmpty ? '—' : waves.join('+');
    final hz = freq * clock / 16777216.0;
    if (hz > 15 && waves.isNotEmpty && (ctrl & 0x80) == 0) {
      final midi = (12 * (math.log(hz / 440) / math.ln2) + 69).round();
      s.note = midi >= 0 ? '${_noteNames[midi % 12]}${midi ~/ 12 - 1}' : '';
    } else {
      s.note = '';
    }
    final target = (s.gate && waves.isNotEmpty) ? math.max(sustain, 0.25) : 0.0;
    s.level = target > s.level
        ? s.level + (target - s.level) * 0.5
        : s.level * 0.9;
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.controller.showChannels;
    return Stack(
      children: [
        channels ? _buildChannels(context) : _buildMix(context),
        // Channel tiles have labels at the top; the mixed scope has none.
        Positioned(
          top: channels ? null : 6,
          bottom: channels ? 4 : null,
          right: channels ? 4 : 6,
          child: _ModeButton(
            channels: channels,
            onPressed: widget.controller.toggleChannelScopes,
          ),
        ),
      ],
    );
  }

  /// Voice state for SID channel [i] (chip * 4 + voice), or null for Digi
  /// and non-SID channels.
  _VoiceState? _voiceFor(int i) {
    if ((widget.controller.info?.sidChips ?? 0) == 0) return null;
    final k = i % 4;
    if (k == 3) return null;
    final v = (i ~/ 4) * 3 + k;
    return v < _voices.length ? _voices[v] : null;
  }

  Widget _buildChannels(BuildContext context) {
    final names = _chanNames.isEmpty
        ? widget.controller.channelNames
        : _chanNames;
    final n = names.length;
    if (n == 0) return _buildMix(context);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final w = box.maxWidth;
        // One row per SID chip when there is room; otherwise fewer columns.
        // Modules with many channels (8 to 32 for .xm) use rows of 8.
        // Too narrow: drop to the next column count that divides the
        // channels evenly (6 -> 3 -> 2), so rows stay full.
        var cols = n > 12 ? 8 : (n % 4 == 0 ? 4 : n);
        final minW = n > 12 ? 60.0 : (n > 4 ? 100.0 : 110.0);
        while (cols > 1 && (w - (cols - 1) * gap) / cols < minW) {
          var next = cols - 1;
          while (next > 1 && n % next != 0) {
            next--;
          }
          cols = next > 1 ? next : cols - 1;
        }
        final rows = (n + cols - 1) ~/ cols;
        final tileW = (w - (cols - 1) * gap) / cols;
        final double tileH;
        if (box.hasBoundedHeight && widget.height == null) {
          tileH = (box.maxHeight - (rows - 1) * gap) / rows;
        } else {
          tileH = rows == 1 ? (widget.height ?? 160) : 84;
        }
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < n; i++)
              SizedBox(
                width: tileW,
                height: tileH,
                child: _ChannelTile(
                  name: names[i],
                  samples: i < _chans.length ? _chans[i] : null,
                  peak: i < _peaks.length ? _peaks[i] : 0,
                  voice: _voiceFor(i),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMix(BuildContext context) {
    final scope = Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF080912),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _ScopePainter(_samples),
          size: Size.infinite,
        ),
      ),
    );
    return Column(
      children: [
        if (widget.height == null) Expanded(child: scope) else scope,
        if (_voices.isNotEmpty) const SizedBox(height: 12),
        if (_voices.isNotEmpty)
          LayoutBuilder(
            builder: (context, box) {
              final perRow = box.maxWidth < 420
                  ? 3
                  : _voices.length.clamp(3, 9);
              final w = (box.maxWidth - (perRow - 1) * 8) / perRow;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _voices.length; i++)
                    SizedBox(
                      width: w,
                      child: _VoiceTile(index: i, state: _voices[i]),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.index, required this.state});
  final int index;
  final _VoiceState state;

  @override
  Widget build(BuildContext context) {
    final col = Palette.voice[index % 3];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: state.gate ? col.withValues(alpha: 0.6) : Palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.gate ? col : Palette.border,
                  boxShadow: state.gate
                      ? [BoxShadow(color: col, blurRadius: 6)]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'V${index + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                state.note,
                style: TextStyle(
                  fontSize: 12,
                  color: col,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.wave,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              fontSize: 11,
              color: Palette.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: state.level.clamp(0, 1),
              minHeight: 5,
              backgroundColor: Palette.panelHigh,
              valueColor: AlwaysStoppedAnimation(col),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(this.samples);
  final Int16List samples;

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final grid = Paint()
      ..color = Palette.scope.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final mid = size.height / 2;
    final path = Path();
    const window = 1024;
    if (samples.length < window + 2) {
      path
        ..moveTo(0, mid)
        ..lineTo(size.width, mid);
    } else {
      // Trigger on a rising zero crossing so the wave stands still.
      var start = 0;
      for (var i = 1; i < samples.length - window; i++) {
        if (samples[i - 1] < 0 && samples[i] >= 0) {
          start = i;
          break;
        }
      }
      final scaleY = size.height * 0.45 / 32768.0 * 2.2; // a little gain
      for (var i = 0; i < window; i++) {
        final x = size.width * i / (window - 1);
        final y = (mid - samples[start + i] * scaleY).clamp(
          2.0,
          size.height - 2,
        );
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    final glow = Paint()
      ..color = Palette.scope.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final line = Paint()
      ..color = Palette.scope
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_ScopePainter old) => !identical(old.samples, samples);
}

/// Small corner button that switches between per-channel and mixed scopes.
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.channels, required this.onPressed});
  final bool channels;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: channels ? 'Show mixed output' : 'Show every channel',
      child: Material(
        color: Palette.panelHigh.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Palette.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  channels ? Icons.grid_view_rounded : Icons.show_chart,
                  size: 14,
                  color: Palette.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  channels ? 'Channels' : 'Mix',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One channel: name (and note/waveform for SID voices) over its scope.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.name,
    required this.samples,
    required this.peak,
    required this.voice,
  });
  final String name;
  final Int16List? samples;
  final double peak;
  final _VoiceState? voice;

  @override
  Widget build(BuildContext context) {
    final col = channelColor(name);
    final active = peak > 600;
    final v = voice;
    final label = name == 'Digi' || name.endsWith(':Digi')
        ? name
        : (RegExp(r'^[ABC]$').hasMatch(name) ? 'Ch $name' : name);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080912),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? col.withValues(alpha: 0.55) : Palette.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _ChannelPainter(samples, col, peak)),
            ),
            Positioned(
              left: 8,
              top: 5,
              right: 8,
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: active ? col : Palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (v != null && v.note.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      v.note,
                      style: TextStyle(
                        fontSize: 11,
                        color: col,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                  if (v != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        v.wave,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Palette.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelPainter extends CustomPainter {
  _ChannelPainter(this.samples, this.color, this.peak);
  final Int16List? samples;
  final Color color;
  final double peak;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2 + 6; // leave room for the label
    final half = size.height / 2 - 10;
    final s = samples;
    // Show about 21 ms: a cycle of a low bass note, readable treble.
    final window = math.min(1024, (s?.length ?? 0) ~/ 2);
    final path = Path();
    if (s == null || window < 16) {
      path
        ..moveTo(0, mid)
        ..lineTo(size.width, mid);
    } else {
      // Trigger on a rising zero crossing in the older half so the wave
      // stands still; the window ends before the newest sample.
      var start = s.length - window;
      for (var i = s.length - window - 1; i > 0; i--) {
        if (s[i - 1] < 0 && s[i] >= 0) {
          start = i;
          break;
        }
      }
      // Auto gain; quiet noise stays small.
      final scale = half * 0.9 / math.max(peak, 3000);
      final step = math.max(1, window ~/ math.max(1, size.width.toInt()));
      for (var i = 0; i < window; i += step) {
        final x = size.width * i / (window - 1);
        final y = (mid - s[start + i] * scale).clamp(1.0, size.height - 1);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_ChannelPainter old) =>
      !identical(old.samples, samples) || old.color != color;
}
