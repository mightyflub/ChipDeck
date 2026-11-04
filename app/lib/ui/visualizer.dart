// Oscilloscope + per-voice SID activity, redrawn every frame while playing.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../player/player_controller.dart';
import 'theme.dart';

class Visualizer extends StatefulWidget {
  const Visualizer({super.key, required this.controller, required this.height});
  final PlayerController controller;
  final double height;

  @override
  State<Visualizer> createState() => _VisualizerState();
}

class _VoiceState {
  double level = 0;
  String wave = '—';
  String note = '';
  bool gate = false;
}

class _VisualizerState extends State<Visualizer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Int16List _samples = Int16List(0);
  List<_VoiceState> _voices = List.generate(3, (_) => _VoiceState());

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
      final busy = _voices.any((v) => v.level > 0.01) || _samples.any((s) => s != 0);
      if (!busy) return;
      setState(() {
        for (final v in _voices) {
          v.level *= 0.85;
          v.gate = false;
        }
        _samples = Int16List(0);
      });
      return;
    }
    final chips = (c.info?.sidChips ?? 1).clamp(1, 3);
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
    setState(() => _samples = c.scope(1536));
  }

  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

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
    s.level = target > s.level ? s.level + (target - s.level) * 0.5 : s.level * 0.9;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
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
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final perRow = box.maxWidth < 420 ? 3 : _voices.length.clamp(3, 9);
        final w = (box.maxWidth - (perRow - 1) * 8) / perRow;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _voices.length; i++)
            SizedBox(width: w, child: _VoiceTile(index: i, state: _voices[i])),
        ]);
      }),
    ]);
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
        border: Border.all(color: state.gate ? col.withValues(alpha: 0.6) : Palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.gate ? col : Palette.border,
              boxShadow: state.gate ? [BoxShadow(color: col, blurRadius: 6)] : null,
            ),
          ),
          const SizedBox(width: 6),
          Text('V${index + 1}',
              style: const TextStyle(fontSize: 11, color: Palette.textMuted, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(state.note,
              style: TextStyle(fontSize: 12, color: col, fontWeight: FontWeight.w700, fontFeatures: tabular)),
        ]),
        const SizedBox(height: 4),
        Text(state.wave,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(fontSize: 11, color: Palette.textMuted, letterSpacing: 0.6)),
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
      ]),
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
        final y = (mid - samples[start + i] * scaleY).clamp(2.0, size.height - 2);
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
