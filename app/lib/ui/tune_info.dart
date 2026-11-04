// Tune info from HVSC STIL.txt and BUGlist.txt: notes on the current
// subtune, the whole tune, known emulation bugs and the composer's folder.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';

import '../hvsc/stil.dart';
import '../player/player_controller.dart';
import 'theme.dart';

/// Whether the current tune can have STIL info (a SID tune with STIL loaded).
bool hasStilSource(PlayerController c) =>
    c.stil != null && c.current != null && (c.info?.sidChips ?? 1) > 0;

class TuneInfoView extends StatelessWidget {
  const TuneInfoView({
    super.key,
    required this.controller,
    this.scrollable = true,
  });
  final PlayerController controller;

  /// Scrolls itself (landscape panel) or lays out in full (inside a page
  /// that already scrolls).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.tuneStil;
    final sub = c.info?.currentSubtune ?? 1;
    final children = <Widget>[];
    if (c.stil == null) {
      children.add(
        const _Empty(
          'Add HVSC STIL.txt in Settings (or add your HVSC folder to the '
          'library) to see notes on tunes and composers.',
        ),
      );
    } else if (s == null || s.isEmpty) {
      children.add(const _Empty('STIL has no notes on this tune.'));
    } else {
      final tune = s.tune;
      final bugs = [...?s.bugs?.global, ...?s.bugs?.subtune(sub)];
      if (tune != null && tune.subtune(sub).isNotEmpty) {
        children.add(
          _Section(
            title: 'Subtune $sub',
            accent: Palette.scope,
            fields: tune.subtune(sub),
          ),
        );
      }
      if (tune != null && tune.global.isNotEmpty) {
        children.add(
          _Section(
            title: 'About this tune',
            accent: Palette.accent,
            fields: tune.global,
          ),
        );
      }
      if (bugs.isNotEmpty) {
        children.add(
          _Section(title: 'Known issues', accent: Palette.warm, fields: bugs),
        );
      }
      for (final f in s.folders) {
        children.add(
          _Section(
            title: 'About ${_folderName(f.path)}',
            accent: Palette.voice[2],
            fields: f.global,
          ),
        );
      }
      final others = [
        for (final n in tune?.subtunes ?? const <int>[])
          if (n != sub && tune!.subtune(n).isNotEmpty) n,
      ];
      if (others.isNotEmpty) {
        children.add(
          _OtherSubtunes(controller: c, entry: tune!, subtunes: others),
        );
      }
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
    if (!scrollable) return column;
    return Material(
      color: Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: column,
        ),
      ),
    );
  }

  /// "/MUSICIANS/H/Hubbard_Rob/" -> "Hubbard Rob".
  static String _folderName(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last.replaceAll('_', ' ');
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Palette.textMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Palette.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.accent,
    required this.fields,
  });
  final String title;
  final Color accent;
  final List<StilField> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          for (final f in fields) _Field(f, accent: accent),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.field, {required this.accent});
  final StilField field;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final f = field;
    switch (f.key) {
      case 'TITLE':
        // A cover or quoted song: starts a new group of fields.
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.music_note_rounded, size: 16, color: accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  f.value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      case 'COMMENT':
      case 'BUG':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            f.value,
            style: TextStyle(
              color: f.key == 'BUG' ? Palette.warm : Colors.white70,
              height: 1.35,
            ),
          ),
        );
      default: // ARTIST, AUTHOR, NAME
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${f.label}  ',
                  style: const TextStyle(
                    color: Palette.textMuted,
                    fontSize: 12,
                  ),
                ),
                TextSpan(text: f.value),
              ],
            ),
          ),
        );
    }
  }
}

/// STIL notes for the subtunes that are not playing, folded away.
class _OtherSubtunes extends StatelessWidget {
  const _OtherSubtunes({
    required this.controller,
    required this.entry,
    required this.subtunes,
  });
  final PlayerController controller;
  final StilEntry entry;
  final List<int> subtunes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          'Notes on ${subtunes.length} other subtune'
          '${subtunes.length == 1 ? '' : 's'}',
          style: const TextStyle(color: Palette.textMuted),
        ),
        children: [
          for (final n in subtunes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => controller.selectSubtune(n),
                child: _Section(
                  title: 'Subtune $n',
                  accent: Palette.textMuted,
                  fields: entry.subtune(n),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Scopes | Info" switch above the right-hand panel (landscape layout).
class PanelSwitch extends StatelessWidget {
  const PanelSwitch({super.key, required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasNotes = !(c.tuneStil?.isEmpty ?? true);
    return Row(
      children: [
        _Pill(
          icon: Icons.graphic_eq,
          label: 'Scopes',
          selected: !c.showTuneInfo,
          onTap: c.showTuneInfo ? c.toggleTuneInfo : null,
        ),
        const SizedBox(width: 6),
        _Pill(
          icon: Icons.article_outlined,
          label: 'Info',
          selected: c.showTuneInfo,
          dot: hasNotes && !c.showTuneInfo,
          onTap: c.showTuneInfo ? null : c.toggleTuneInfo,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Marks that there is something to read.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final col = selected ? Palette.accent : Palette.textMuted;
    return Material(
      color: selected
          ? Palette.accent.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Palette.accent : Palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: col),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: col,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (dot) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Palette.scope,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
