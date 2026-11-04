// Dual-screen support (Ayn Thor and other handhelds with a second display):
// the player controls run on the other screen (lib/ui/controls_screen.dart,
// started by SecondScreen.kt). This side mirrors the player state to them
// and applies their actions. Android only; nothing happens elsewhere.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/player_controller.dart';
import 'remote_controls.dart';

/// True while the controls are showing on a second screen; the main screen
/// then leaves out its own transport buttons.
final secondScreenActive = ValueNotifier<bool>(false);

/// The user's choice in Settings (default on).
final secondScreenEnabled = ValueNotifier<bool>(true);

const _prefKey = 'secondScreenControls';

Future<void> loadSecondScreenSetting() async {
  final prefs = await SharedPreferences.getInstance();
  secondScreenEnabled.value = prefs.getBool(_prefKey) ?? true;
}

Future<void> setSecondScreenEnabled(bool on) async {
  secondScreenEnabled.value = on;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKey, on);
}

/// Brings the controls back in front on the second screen (after another
/// app there covered them).
Future<void> raiseSecondScreen() =>
    const MethodChannel('chipdeck/android').invokeMethod('raiseSecondScreen');

/// Builds the state message for the controls screen.
Map<String, Object?> remoteStateOf(PlayerController c) =>
    RemoteState.of(c).toMap();
