// Visual theme: dark, retro-tinted, readable.
import 'package:flutter/material.dart';

import '../native/chipdeck_ffi.dart' show TuneSystem;

class Palette {
  static const background = Color(0xFF0E0F1A);
  static const panel = Color(0xFF161829);
  static const panelHigh = Color(0xFF1E2138);
  static const border = Color(0xFF2A2E4D);
  static const accent = Color(0xFF8E7CFF); // C64-ish light blue/violet
  static const scope = Color(0xFF5CE1E6); // phosphor cyan
  static const warm = Color(0xFFFFB86B); // Atari ST
  static const amiga = Color(0xFF7CE38B); // Amiga / tracker modules
  static const textMuted = Color(0xFF9AA0C3);
  static const voice = [
    Color(0xFF8E7CFF),
    Color(0xFF5CE1E6),
    Color(0xFFFF7AB6),
  ];
}

/// Badge colour for a tune's machine.
Color systemColor(TuneSystem s) => switch (s) {
  TuneSystem.c64 => Palette.scope,
  TuneSystem.atariSt => Palette.warm,
  TuneSystem.amiga || TuneSystem.pc => Palette.amiga,
};

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Palette.accent,
        secondary: Palette.scope,
        surface: Palette.panel,
        surfaceContainerHighest: Palette.panelHigh,
        outlineVariant: Palette.border,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    dividerTheme: const DividerThemeData(color: Palette.border, thickness: 1),
    listTileTheme: const ListTileThemeData(dense: true),
  );
}

const tabular = [FontFeature.tabularFigures()];

String formatMs(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
