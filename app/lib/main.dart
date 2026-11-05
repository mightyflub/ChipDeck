// ChipDeck: retro chiptune player.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';

import 'debug_switches.dart';

import 'library/library.dart';
import 'native_licenses.dart';
import 'platform/android_media.dart';
import 'platform/second_screen.dart';
import 'ui/controls_screen.dart';
import 'player/player_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  final controller = await PlayerController.create();
  final library = await LibraryController.create();
  library.songlengthsPath = () => controller.songlengthsPath;
  library.onSonglengthsFound = (path) => controller.setSonglengths(path);
  library.stilPath = () => controller.stilPath;
  library.onStilFound = (path) => controller.setStil(path);
  // A new Songlengths file changes lengths for every tune: refresh the index.
  controller.onSonglengthsChanged = () => library.rescan(full: true);
  await loadSecondScreenSetting();
  AndroidMedia.attach(controller);
  runApp(ChipDeckApp(controller: controller, library: library));
  // Pick up tunes added to the archive since last time (only new or
  // changed files are read, so this is quick).
  if (!dbgNoRescan) library.rescan();
}

/// Entry point for the player controls on a second screen (dual-screen
/// handhelds). Started by SecondScreen.kt in its own Flutter engine.
@pragma('vm:entry-point')
void controlsMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ControlsApp());
}

class ChipDeckApp extends StatelessWidget {
  const ChipDeckApp({
    super.key,
    required this.controller,
    required this.library,
  });

  final PlayerController controller;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChipDeck',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: dbgNoSemantics
          ? ExcludeSemantics(
              child: HomePage(controller: controller, library: library),
            )
          : HomePage(controller: controller, library: library),
    );
  }
}
