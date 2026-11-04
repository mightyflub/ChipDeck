// Settings: SID model, Songlengths database, default length, about.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../native/chipdeck_ffi.dart';
import '../player/player_controller.dart';
import 'theme.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.controller});
  final PlayerController controller;

  static const _lengths = <int, String>{
    60: '1 minute',
    120: '2 minutes',
    180: '3 minutes',
    300: '5 minutes',
    600: '10 minutes',
    0: 'Forever',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return AlertDialog(
          backgroundColor: Palette.panel,
          title: const Text('Settings'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _Label('SID chip model'),
                const SizedBox(height: 8),
                SegmentedButton<SidModel>(
                  segments: const [
                    ButtonSegment(value: SidModel.auto, label: Text('Auto')),
                    ButtonSegment(value: SidModel.mos6581, label: Text('6581')),
                    ButtonSegment(value: SidModel.mos8580, label: Text('8580')),
                  ],
                  selected: {c.sidModel},
                  onSelectionChanged: (s) => c.setSidModel(s.first),
                ),
                const SizedBox(height: 6),
                const Text('Auto uses the model the tune asks for. 6581 is the warmer original chip.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12)),
                const SizedBox(height: 22),
                const _Label('Song lengths (HVSC Songlengths.md5)'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      c.songlengthsPath ?? 'Not set: songs use the default length below.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.songlengthsPath == null ? Palette.textMuted : Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final f = await openFile(acceptedTypeGroups: const [
                        XTypeGroup(label: 'Songlengths', extensions: ['md5', 'txt']),
                      ]);
                      if (f != null) c.setSonglengths(f.path);
                    },
                    child: const Text('Choose…'),
                  ),
                  if (c.songlengthsPath != null)
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: () => c.setSonglengths(null),
                      icon: const Icon(Icons.close),
                    ),
                ]),
                const SizedBox(height: 6),
                const Text('Found in HVSC at C64Music/DOCUMENTS/Songlengths.md5.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12)),
                const SizedBox(height: 22),
                const _Label('Default song length'),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: _lengths.containsKey(c.defaultLengthSec) ? c.defaultLengthSec : 180,
                  dropdownColor: Palette.panelHigh,
                  onChanged: (v) => c.setDefaultLength(v ?? 180),
                  items: [
                    for (final e in _lengths.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                ),
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 8),
                Text('ChipDeck ${c.engineVersion}',
                    style: const TextStyle(color: Palette.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                const Text(
                    'SID emulation by libsidplayfp and reSIDfp. Free software under the GNU GPL v2 or later.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                const Text(
                    'Keys: Space play/pause · ←/→ subtune · N/P next/previous tune · +/- volume',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12)),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => showLicensePage(context: context, applicationName: 'ChipDeck'),
              child: const Text('Licenses'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: Palette.textMuted, letterSpacing: 1.2, fontWeight: FontWeight.w700));
}
