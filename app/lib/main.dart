// ChipDeck: retro chiptune player.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/material.dart';

import 'player/player_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await PlayerController.create();
  runApp(ChipDeckApp(controller: controller));
}

class ChipDeckApp extends StatelessWidget {
  const ChipDeckApp({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChipDeck',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(controller: controller),
    );
  }
}
