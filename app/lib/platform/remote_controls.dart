// What the player-controls screen shows and the actions it sends back.
// Used for the second screen of dual-screen devices (Ayn Thor and others),
// where the controls run in their own Flutter engine and only see this
// state, sent over a method channel.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import '../native/chipdeck_ffi.dart' show TuneSystem;
import '../player/player_controller.dart';

class RemoteState {
  const RemoteState({
    this.hasTune = false,
    this.title = '',
    this.author = '',
    this.released = '',
    this.format = '',
    this.system = TuneSystem.c64,
    this.playing = false,
    this.positionMs = 0,
    this.lengthMs,
    this.lengthKnown = false,
    this.subtune = 0,
    this.subtunes = 0,
    this.startSubtune = 0,
    this.volume = 0.8,
    this.advance = 0,
    this.playlistIndex = 0,
    this.playlistLength = 0,
    this.shuffle = false,
    this.muted = 0,
    this.canSeek = false,
  });

  final bool hasTune;
  final String title;
  final String author;
  final String released;
  final String format;
  final TuneSystem system;
  final bool playing;
  final int positionMs;
  final int? lengthMs;
  final bool lengthKnown;
  final int subtune;
  final int subtunes;
  final int startSubtune;
  final double volume;
  final int advance; // AdvanceMode index
  final int playlistIndex; // 1-based, 0 = none
  final int playlistLength;
  final bool shuffle;
  final int muted; // number of muted channels
  final bool canSeek;

  static RemoteState of(PlayerController c) {
    final e = c.current;
    final i = c.info;
    return RemoteState(
      hasTune: e != null,
      title: e?.title ?? '',
      author: i?.author ?? e?.author ?? '',
      released: i?.released ?? '',
      format: i?.format ?? '',
      system: i?.system ?? TuneSystem.c64,
      playing: c.playing,
      positionMs: c.positionMs,
      lengthMs: c.effectiveLengthMs,
      lengthKnown: c.lengthIsKnown,
      subtune: i?.currentSubtune ?? 0,
      subtunes: i?.subtunes ?? 0,
      startSubtune: i?.startSubtune ?? 0,
      volume: c.volume,
      advance: c.advanceMode.index,
      playlistIndex: c.listPosition,
      playlistLength: c.listLength,
      shuffle: c.shuffle,
      muted: _bitCount(c.muteMask),
      canSeek: c.canSeek,
    );
  }

  static int _bitCount(int m) {
    var n = 0;
    for (; m != 0; m &= m - 1) {
      n++;
    }
    return n;
  }

  Map<String, Object?> toMap() => {
    'hasTune': hasTune,
    'title': title,
    'author': author,
    'released': released,
    'format': format,
    'system': system.index,
    'playing': playing,
    'positionMs': positionMs,
    'lengthMs': lengthMs,
    'lengthKnown': lengthKnown,
    'subtune': subtune,
    'subtunes': subtunes,
    'startSubtune': startSubtune,
    'volume': volume,
    'advance': advance,
    'playlistIndex': playlistIndex,
    'playlistLength': playlistLength,
    'shuffle': shuffle,
    'muted': muted,
    'canSeek': canSeek,
  };

  static RemoteState fromMap(Map<Object?, Object?> m) => RemoteState(
    hasTune: m['hasTune'] as bool? ?? false,
    title: m['title'] as String? ?? '',
    author: m['author'] as String? ?? '',
    released: m['released'] as String? ?? '',
    format: m['format'] as String? ?? '',
    system: TuneSystem.fromIndex((m['system'] as num?)?.toInt() ?? 0),
    playing: m['playing'] as bool? ?? false,
    positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
    lengthMs: (m['lengthMs'] as num?)?.toInt(),
    lengthKnown: m['lengthKnown'] as bool? ?? false,
    subtune: (m['subtune'] as num?)?.toInt() ?? 0,
    subtunes: (m['subtunes'] as num?)?.toInt() ?? 0,
    startSubtune: (m['startSubtune'] as num?)?.toInt() ?? 0,
    volume: (m['volume'] as num?)?.toDouble() ?? 0.8,
    advance: (m['advance'] as num?)?.toInt() ?? 0,
    playlistIndex: (m['playlistIndex'] as num?)?.toInt() ?? 0,
    playlistLength: (m['playlistLength'] as num?)?.toInt() ?? 0,
    shuffle: m['shuffle'] as bool? ?? false,
    muted: (m['muted'] as num?)?.toInt() ?? 0,
    canSeek: m['canSeek'] as bool? ?? false,
  );
}

/// Applies an action from the controls screen to the player.
void applyRemoteAction(PlayerController c, String action, Object? value) {
  switch (action) {
    case 'toggle':
      c.togglePlay();
    case 'next':
      c.nextTrack();
    case 'previous':
      c.previousTrack();
    case 'shuffle':
      c.toggleShuffle();
    case 'nextSubtune':
      c.nextSubtune();
    case 'previousSubtune':
      c.previousSubtune();
    case 'seek':
      if (value is num) c.seekTo(value.toInt());
    case 'unmuteAll':
      c.unmuteAll();
    case 'subtune':
      if (value is num) c.selectSubtune(value.toInt());
    case 'volume':
      if (value is num) c.setVolume(value.toDouble().clamp(0, 1));
    case 'advance':
      if (value is num) {
        c.setAdvanceMode(
          AdvanceMode.values[value.toInt().clamp(
            0,
            AdvanceMode.values.length - 1,
          )],
        );
      }
  }
}
