// Now playing: tune details, visualiser, progress, transport, subtunes.
import 'package:flutter/material.dart';

import '../native/chipdeck_ffi.dart';
import '../player/player_controller.dart';
import 'theme.dart';
import 'visualizer.dart';

class NowPlaying extends StatelessWidget {
  const NowPlaying({
    super.key,
    required this.controller,
    required this.compact,
  });

  final PlayerController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final info = c.info;
        final pad = compact ? 16.0 : 32.0;
        return LayoutBuilder(
          builder: (context, box) {
            // Short, wide screens (phones and handhelds in landscape):
            // details and controls on the left, visualiser on the right,
            // all on one screen without scrolling.
            if (box.maxHeight < 560 && box.maxWidth >= 560) {
              return _Landscape(controller: c, info: info);
            }
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - pad * 2),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(controller: c, info: info, compact: compact),
                        SizedBox(height: compact ? 16 : 24),
                        Visualizer(controller: c, height: compact ? 140 : 190),
                        SizedBox(height: compact ? 16 : 24),
                        _Progress(controller: c),
                        const SizedBox(height: 12),
                        _Transport(controller: c),
                        if (info != null && info.subtunes > 1) ...[
                          const SizedBox(height: 20),
                          _Subtunes(controller: c, info: info),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Landscape extends StatelessWidget {
  const _Landscape({required this.controller, required this.info});
  final PlayerController controller;
  final TuneInfo? info;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final i = info;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: _Header(controller: c, info: i, compact: true),
                  ),
                ),
                if (i != null && i.subtunes > 1) ...[
                  const SizedBox(height: 6),
                  _SubtuneStrip(controller: c, info: i),
                ],
                const SizedBox(height: 8),
                _Progress(controller: c),
                _Transport(controller: c, dense: true),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 9, child: Visualizer(controller: c)),
        ],
      ),
    );
  }
}

/// Subtune buttons in one scrollable row (landscape layout).
class _SubtuneStrip extends StatefulWidget {
  const _SubtuneStrip({required this.controller, required this.info});
  final PlayerController controller;
  final TuneInfo info;

  @override
  State<_SubtuneStrip> createState() => _SubtuneStripState();
}

class _SubtuneStripState extends State<_SubtuneStrip> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_SubtuneStrip old) {
    super.didUpdateWidget(old);
    // Keep the current subtune in view when it changes.
    if (old.info.currentSubtune != widget.info.currentSubtune &&
        _scroll.hasClients) {
      final x = (widget.info.currentSubtune - 1) * 44.0 - 80;
      _scroll.animateTo(
        x.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Text(
            '${info.currentSubtune}/${info.subtunes}',
            style: const TextStyle(
              color: Palette.textMuted,
              fontSize: 12,
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: info.subtunes,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, k) => _SubtuneButton(
                n: k + 1,
                selected: k + 1 == info.currentSubtune,
                isDefault: k + 1 == info.startSubtune,
                onTap: () => widget.controller.selectSubtune(k + 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.info,
    required this.compact,
  });
  final PlayerController controller;
  final TuneInfo? info;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final entry = controller.current;
    if (entry == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing playing',
            style: (compact ? t.headlineSmall : t.headlineMedium)?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick a tune from your library or playlist.',
            style: TextStyle(color: Palette.textMuted),
          ),
        ],
      );
    }
    final i = info;
    final model = switch (i?.sidModel) {
      SidModel.mos8580 => '8580',
      SidModel.mos6581 => '6581',
      _ => null,
    };
    final forced = controller.sidModel != SidModel.auto;
    final isSid = (i?.sidChips ?? 1) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (i != null) _Chip(_shortFormat(i.format)),
            if (i != null && !isSid) const _Chip('Atari ST', highlight: true),
            if (isSid && model != null)
              _Chip(forced ? '$model (forced)' : model, highlight: true),
            if (i != null && isSid) _Chip(i.isNtsc ? 'NTSC' : 'PAL'),
            if (i != null && i.sidChips > 1)
              _Chip('${i.sidChips}SID', highlight: true),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (compact ? t.headlineSmall : t.displaySmall)?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        if ((i?.author ?? '').isNotEmpty)
          Text(
            i!.author,
            style: (compact ? t.titleMedium : t.titleLarge)?.copyWith(
              color: Palette.accent,
            ),
          ),
        if ((i?.released ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(i!.released, style: const TextStyle(color: Palette.textMuted)),
        ],
      ],
    );
  }

  static String _shortFormat(String f) {
    if (f.contains('RSID')) return 'RSID';
    if (f.contains('PSID')) return 'PSID';
    if (f.length > 18) return f.substring(0, 18);
    return f;
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final col = highlight ? Palette.scope : Palette.textMuted;
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

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final len = c.effectiveLengthMs;
    final pos = c.positionMs;
    final frac = len == null || len == 0 ? 0.0 : (pos / len).clamp(0.0, 1.0);
    final lenText = len == null
        ? '∞'
        : '${c.lengthIsKnown ? '' : '~'}${formatMs(len)}';
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: len == null ? 0 : frac,
            minHeight: 6,
            backgroundColor: Palette.panelHigh,
            valueColor: const AlwaysStoppedAnimation(Palette.accent),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              formatMs(pos),
              style: const TextStyle(
                color: Palette.textMuted,
                fontFeatures: tabular,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: c.lengthIsKnown
                  ? 'Length from Songlengths database'
                  : (len == null
                        ? 'Plays until you skip (set a default length in Settings)'
                        : 'Default length (add HVSC Songlengths.md5 in Settings for real lengths)'),
              child: Text(
                lenText,
                style: const TextStyle(
                  color: Palette.textMuted,
                  fontFeatures: tabular,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, this.dense = false});
  final PlayerController controller;

  /// Landscape: one row with smaller buttons; volume as a pop-up.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final i = c.info;
    final hasTune = c.current != null;
    final canPrevSub = i != null && i.currentSubtune > 1;
    final canNextSub = i != null && i.currentSubtune < i.subtunes;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 520;
        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous tune (P)',
              iconSize: 28,
              onPressed: c.playlist.isEmpty ? null : c.previousTrack,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton(
              tooltip: 'Previous subtune (←)',
              iconSize: 26,
              onPressed: canPrevSub ? c.previousSubtune : null,
              icon: const Icon(Icons.fast_rewind_rounded),
            ),
            const SizedBox(width: 8),
            _PlayButton(
              playing: c.playing,
              onPressed: hasTune || c.playlist.isNotEmpty ? c.togglePlay : null,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Next subtune (→)',
              iconSize: 26,
              onPressed: canNextSub ? c.nextSubtune : null,
              icon: const Icon(Icons.fast_forward_rounded),
            ),
            IconButton(
              tooltip: 'Next tune (N)',
              iconSize: 28,
              onPressed: c.playlist.isEmpty ? null : c.nextTrack,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        );
        final volume = _Volume(controller: c);
        final advance = _AdvanceButton(controller: c);
        if (dense) {
          return Row(
            children: [
              advance,
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Transform.scale(scale: 0.85, child: buttons),
                ),
              ),
              _VolumeButton(controller: c),
            ],
          );
        }
        if (narrow) {
          return Column(
            children: [
              buttons,
              const SizedBox(height: 8),
              Row(
                children: [
                  advance,
                  Expanded(child: volume),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 200,
              child: Align(alignment: Alignment.centerLeft, child: advance),
            ),
            Expanded(child: Center(child: buttons)),
            SizedBox(width: 200, child: volume),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});
  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: playing ? 'Pause (Space)' : 'Play (Space)',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: Palette.accent.withValues(alpha: 0.45),
                    blurRadius: 22,
                  ),
                ],
        ),
        child: IconButton.filled(
          iconSize: 38,
          style: IconButton.styleFrom(
            backgroundColor: Palette.accent,
            foregroundColor: Palette.background,
            minimumSize: const Size(64, 64),
          ),
          onPressed: onPressed,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.volume;
    return Row(
      children: [
        IconButton(
          tooltip: 'Volume (+/-)',
          icon: Icon(
            v == 0
                ? Icons.volume_off
                : (v < 0.5 ? Icons.volume_down : Icons.volume_up),
            color: Palette.textMuted,
          ),
          onPressed: () => controller.setVolume(v == 0 ? 0.8 : 0),
        ),
        Expanded(
          child: Slider(value: v, onChanged: controller.setVolume),
        ),
      ],
    );
  }
}

/// Volume icon that opens a slider (landscape layout, where a full-width
/// slider does not fit).
class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.volume;
    return IconButton(
      tooltip: 'Volume (+/-)',
      icon: Icon(
        v == 0
            ? Icons.volume_off
            : (v < 0.5 ? Icons.volume_down : Icons.volume_up),
        color: Palette.textMuted,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Volume'),
          content: SizedBox(
            width: 320,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => _Volume(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvanceButton extends StatelessWidget {
  const _AdvanceButton({required this.controller});
  final PlayerController controller;

  static const _labels = {
    AdvanceMode.subtunesThenNext: 'Play all subtunes, then next tune',
    AdvanceMode.nextFile: 'Next tune when a song ends',
    AdvanceMode.repeatOne: 'Repeat current subtune',
  };
  static const _icons = {
    AdvanceMode.subtunesThenNext: Icons.playlist_play,
    AdvanceMode.nextFile: Icons.arrow_right_alt,
    AdvanceMode.repeatOne: Icons.repeat_one,
  };

  @override
  Widget build(BuildContext context) {
    final m = controller.advanceMode;
    return PopupMenuButton<AdvanceMode>(
      tooltip: 'When a song ends: ${_labels[m]}',
      initialValue: m,
      onSelected: controller.setAdvanceMode,
      itemBuilder: (_) => [
        for (final mode in AdvanceMode.values)
          PopupMenuItem(
            value: mode,
            child: Row(
              children: [
                Icon(_icons[mode], size: 20),
                const SizedBox(width: 10),
                Text(_labels[mode]!),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(_icons[m], color: Palette.textMuted),
      ),
    );
  }
}

class _Subtunes extends StatelessWidget {
  const _Subtunes({required this.controller, required this.info});
  final PlayerController controller;
  final TuneInfo info;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SUBTUNES',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Palette.textMuted, letterSpacing: 1.4),
            ),
            const SizedBox(width: 8),
            Text(
              '${info.currentSubtune} of ${info.subtunes}',
              style: const TextStyle(
                color: Palette.textMuted,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var n = 1; n <= info.subtunes; n++)
              _SubtuneButton(
                n: n,
                selected: n == info.currentSubtune,
                isDefault: n == info.startSubtune,
                onTap: () => controller.selectSubtune(n),
              ),
          ],
        ),
      ],
    );
  }
}

class _SubtuneButton extends StatelessWidget {
  const _SubtuneButton({
    required this.n,
    required this.selected,
    required this.isDefault,
    required this.onTap,
  });
  final int n;
  final bool selected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isDefault ? 'Subtune $n (default)' : 'Subtune $n',
      child: Material(
        color: selected ? Palette.accent : Palette.panelHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDefault && !selected
                    ? Palette.accent.withValues(alpha: 0.6)
                    : Palette.border,
              ),
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: tabular,
                color: selected ? Palette.background : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
