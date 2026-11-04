// Android background playback: keeps a foreground service with a media
// notification running while a tune plays, and routes its buttons (and
// headphone unplugging) back to the player. Does nothing on desktop.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:io';

import 'package:flutter/services.dart';

import '../player/player_controller.dart';
import 'remote_controls.dart';
import 'second_screen.dart';

class AndroidMedia {
  AndroidMedia._(this._player);

  static const _channel = MethodChannel('chipdeck/android');

  final PlayerController _player;
  String? _lastKey;

  /// Starts mirroring [player] into the Android notification.
  static void attach(PlayerController player) {
    if (!Platform.isAndroid) return;
    final m = AndroidMedia._(player);
    _channel.setMethodCallHandler(m._onCall);
    player.addListener(m._sync);
    player.addListener(m._syncControls);
    void sendEnabled() => _channel.invokeMethod(
      'setSecondScreenEnabled',
      secondScreenEnabled.value,
    );
    secondScreenEnabled.addListener(sendEnabled);
    sendEnabled();
  }

  /// Sends the player state to the second-screen controls, if showing.
  void _syncControls() {
    if (!secondScreenActive.value) return;
    _channel.invokeMethod('controlsState', remoteStateOf(_player));
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'secondScreen':
        secondScreenActive.value = call.arguments == true;
        _syncControls();
        return null;
      case 'controlsReady':
        _syncControls();
        return null;
      case 'controlsAction':
        final m = call.arguments as Map;
        applyRemoteAction(_player, m['action'] as String, m['value']);
        return null;
    }
    if (call.method != 'mediaAction') return null;
    switch (call.arguments as String?) {
      case 'toggle':
        _player.togglePlay();
      case 'play':
        if (!_player.playing) _player.togglePlay();
      case 'pause':
        if (_player.playing) _player.togglePlay();
      case 'next':
        _player.nextTrack();
      case 'previous':
        _player.previousTrack();
      case 'stop':
        _player.stop();
    }
    return null;
  }

  void _sync() {
    final entry = _player.current;
    final info = _player.info;
    final active = entry != null && info != null;
    final title = entry?.title ?? '';
    final author = entry?.author ?? '';
    final sub = info == null || info.subtunes <= 1
        ? ''
        : ' (${info.currentSubtune}/${info.subtunes})';
    final text = author.isEmpty ? info?.format ?? '' : author;
    final key = '$active|${_player.playing}|$title$sub|$text';
    if (key == _lastKey) return; // the player notifies every 200 ms
    _lastKey = key;
    if (!active) {
      _channel.invokeMethod('stopPlaybackService');
      return;
    }
    _channel.invokeMethod('updatePlaybackService', {
      'title': '$title$sub',
      'text': text,
      'playing': _player.playing,
    });
  }
}
