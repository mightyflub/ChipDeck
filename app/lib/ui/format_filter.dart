// Library format filter: one button that opens a panel of systems and
// formats with tune counts. Replaces the row of chips, which ran out of
// room as formats were added; a new format is one line in formatGroups.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';

import '../library/library.dart';
import 'theme.dart';

class FormatFilterButton extends StatefulWidget {
  const FormatFilterButton({
    super.key,
    required this.filter,
    required this.counts,
    required this.onChanged,
    this.dense = false,
  });

  final FormatFilter filter;
  final Map<String, int> counts;
  final ValueChanged<FormatFilter> onChanged;

  /// Short toolbars (landscape handhelds): smaller button, shorter label.
  final bool dense;

  @override
  State<FormatFilterButton> createState() => _FormatFilterButtonState();
}

class _FormatFilterButtonState extends State<FormatFilterButton> {
  final _menu = MenuController();
  // The open panel listens to this, so it updates while it is open.
  late final _filter = ValueNotifier(widget.filter);

  @override
  void didUpdateWidget(FormatFilterButton old) {
    super.didUpdateWidget(old);
    if (widget.filter != _filter.value) _filter.value = widget.filter;
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _set(FormatFilter f) {
    _filter.value = f;
    widget.onChanged(f);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final active = !f.isAll;
    final label = f.summary;
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Palette.panelHigh),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Palette.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        ValueListenableBuilder<FormatFilter>(
          valueListenable: _filter,
          builder: (context, value, _) => _FilterPanel(
            filter: value,
            counts: widget.counts,
            onChanged: _set,
            onDone: _menu.close,
          ),
        ),
      ],
      builder: (context, menu, _) {
        final style = OutlinedButton.styleFrom(
          foregroundColor: active ? Palette.accent : Colors.white,
          backgroundColor: active
              ? Palette.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          side: BorderSide(
            color: active
                ? Palette.accent.withValues(alpha: 0.6)
                : Palette.border,
          ),
          visualDensity: widget.dense ? VisualDensity.compact : null,
          tapTargetSize: widget.dense
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 10 : 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );
        return Tooltip(
          message: active ? 'Showing: $label' : 'Filter by format',
          child: OutlinedButton(
            style: style,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list, size: widget.dense ? 18 : 20),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.dense ? 90 : 160,
                  ),
                  child: Text(
                    widget.dense && !active ? 'Formats' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filter,
    required this.counts,
    required this.onChanged,
    required this.onDone,
  });

  final FormatFilter filter;
  final Map<String, int> counts;
  final ValueChanged<FormatFilter> onChanged;
  final VoidCallback onDone;

  static const _groupWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Short, wide screens (handhelds in landscape): systems in two columns
    // so the whole panel fits without scrolling.
    final screen = MediaQuery.sizeOf(context);
    final twoCols = screen.height < 560 && screen.width >= 740;
    final groups = [
      for (final (sys, name, formats) in formatGroups)
        SizedBox(
          width: _groupWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SystemRow(
                name: name,
                count: formats.fold(0, (n, f) => n + (counts[f.key] ?? 0)),
                // Tristate: all, some or none of the system's formats.
                value: filter.hasSystem(sys)
                    ? true
                    : formats.any((f) => filter.keys.contains(f.key))
                    ? null
                    : false,
                onTap: () => onChanged(filter.toggleSystem(sys)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 0, 0, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in formats)
                      _FormatChip(
                        label: f.label,
                        count: counts[f.key] ?? 0,
                        selected: filter.keys.contains(f.key),
                        onTap: () => onChanged(filter.toggle(f.key)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: SizedBox(
        width: twoCols ? _groupWidth * 2 + 12 : _groupWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                Text(
                  'FORMATS',
                  style: t.labelMedium?.copyWith(
                    color: Palette.textMuted,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: filter.isAll
                      ? null
                      : () => onChanged(FormatFilter.all),
                  child: const Text('Show all'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: onDone,
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 12, children: groups),
          ],
        ),
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  const _SystemRow({
    required this.name,
    required this.count,
    required this.value,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Row(
        children: [
          Checkbox(
            value: value,
            tristate: true,
            visualDensity: VisualDensity.compact,
            onChanged: (_) => onTap(),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              _count(count),
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 12,
                fontFeatures: tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label),
            TextSpan(
              text: '  ${_count(count)}',
              style: TextStyle(
                color: selected ? Colors.white : Palette.textMuted,
                fontSize: 11,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        style: TextStyle(
          color: count == 0 && !selected ? Palette.textMuted : null,
        ),
      ),
    );
  }
}

String _count(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
