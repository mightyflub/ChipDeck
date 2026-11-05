// Settings: SID model, Songlengths database, default length, about.
import '../version.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import '../native/chipdeck_ffi.dart';
import '../platform/files.dart' as files;
import '../platform/second_screen.dart';
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
          title: Row(
            children: [
              const Text('Settings'),
              const Spacer(),
              Text(
                'ChipDeck $appVersion',
                style: const TextStyle(color: Palette.textMuted, fontSize: 12),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('SID chip model'),
                  const SizedBox(height: 8),
                  SegmentedButton<SidModel>(
                    segments: const [
                      ButtonSegment(value: SidModel.auto, label: Text('Auto')),
                      ButtonSegment(
                        value: SidModel.mos6581,
                        label: Text('6581'),
                      ),
                      ButtonSegment(
                        value: SidModel.mos8580,
                        label: Text('8580'),
                      ),
                    ],
                    selected: {c.sidModel},
                    onSelectionChanged: (s) => c.setSidModel(s.first),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Auto uses the model the tune asks for. 6581 is the warmer original chip.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 22),
                  const _Label('Song lengths (HVSC Songlengths.md5)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.songlengthsPath ??
                              'Not set: songs use the default length below.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.songlengthsPath == null
                                ? Palette.textMuted
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final f = await files.pickSingleFile(
                            context,
                            label: 'Songlengths',
                            extensions: ['md5', 'txt'],
                          );
                          if (f != null) c.setSonglengths(f);
                        },
                        child: const Text('Choose…'),
                      ),
                      if (c.songlengthsPath != null)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => c.setSonglengths(null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Found in HVSC at C64Music/DOCUMENTS/Songlengths.md5.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 22),
                  const _Label('Tune info (HVSC STIL.txt)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.stilPath ?? 'Not set: no composer or tune notes for SID tunes.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.stilPath == null
                                ? Palette.textMuted
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final f = await files.pickSingleFile(
                            context,
                            label: 'STIL',
                            extensions: ['txt'],
                          );
                          if (f != null) c.setStil(f);
                        },
                        child: const Text('Choose…'),
                      ),
                      if (c.stilPath != null)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => c.setStil(null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.stil == null
                        ? 'Found in HVSC at C64Music/DOCUMENTS/STIL.txt. BUGlist.txt beside it is read too.'
                        : '${c.stil!.entryCount} entries. BUGlist.txt beside it is read too.',
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _Label('C64 ROMs (optional)'),
                  const SizedBox(height: 8),
                  _RomRow(controller: c, which: 'basic', name: 'BASIC'),
                  _RomRow(controller: c, which: 'kernal', name: 'KERNAL'),
                  _RomRow(controller: c, which: 'chargen', name: 'Characters'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'C64 BASIC tunes need the BASIC ROM; KERNAL and characters help a few RSID tunes. '
                          'Use the ROM files from an emulator such as VICE.',
                          style: TextStyle(
                            color: Palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final dir = await files.pickFolder(context);
                          if (dir == null) return;
                          final n = c.findRoms(dir);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                n == 0
                                    ? 'No C64 ROMs found in that folder (looked for kernal*, basic* and chargen* files).'
                                    : 'Found $n C64 ROM${n == 1 ? '' : 's'}.',
                              ),
                            ),
                          );
                        },
                        child: const Text('Find in folder…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _Label('Default song length'),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: _lengths.containsKey(c.defaultLengthSec)
                        ? c.defaultLengthSec
                        : 180,
                    dropdownColor: Palette.panelHigh,
                    onChanged: (v) => c.setDefaultLength(v ?? 180),
                    items: [
                      for (final e in _lengths.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: secondScreenEnabled,
                      builder: (_, on, _) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Controls on second screen'),
                        subtitle: const Text(
                          'On dual-screen devices such as the Ayn Thor, show the player controls on the other screen.',
                          style: TextStyle(
                            color: Palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        value: on,
                        onChanged: setSecondScreenEnabled,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'ChipDeck ${c.engineVersion}',
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'SID emulation by libsidplayfp and reSIDfp, Atari ST by AtariAudio, '
                    'MOD/XM by libxmp, TFMX and Future Composer by libtfmxaudiodecoder. '
                    'Free software under the GNU GPL v2 or later.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keys: Space play/pause · ←/→ subtune · Shift+←/→ jump 10 s · '
                    'N/P next/previous tune · 1-9 mute a channel, 0 unmute all · +/- volume. '
                    'Click a scope to mute it, right-click (long press) to hear only that one.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'ChipDeck',
                applicationVersion: appVersion,
              ),
              child: const Text('Licenses'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

/// One C64 ROM setting: file name, choose, clear.
class _RomRow extends StatelessWidget {
  const _RomRow({
    required this.controller,
    required this.which,
    required this.name,
  });
  final PlayerController controller;
  final String which;
  final String name;

  String? get _path => switch (which) {
    'kernal' => controller.kernalPath,
    'basic' => controller.basicPath,
    _ => controller.chargenPath,
  };

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            path == null ? 'Not set' : path.split(RegExp(r'[\\/]')).last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: path == null ? Palette.textMuted : Colors.white,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            final f = await files.pickSingleFile(
              context,
              label: '$name ROM',
              extensions: const [],
            );
            if (f == null) return;
            final err = controller.setRom(which, f);
            if (err != null && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(err)));
            }
          },
          child: const Text('Choose…'),
        ),
        if (path != null)
          IconButton(
            tooltip: 'Clear',
            onPressed: () => controller.setRom(which, null),
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Palette.textMuted,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    ),
  );
}
