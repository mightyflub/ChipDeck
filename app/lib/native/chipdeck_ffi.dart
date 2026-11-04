// dart:ffi bindings for the ChipDeck native core (core/include/chipdeck/chipdeck.h).
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Mirrors `cd_info` in chipdeck.h. Keep the layout identical.
final class CdInfoStruct extends Struct {
  @Array(64)
  external Array<Uint8> title;
  @Array(64)
  external Array<Uint8> author;
  @Array(64)
  external Array<Uint8> released;
  @Array(64)
  external Array<Uint8> format;
  @Int32()
  external int subtunes;
  @Int32()
  external int startSubtune;
  @Int32()
  external int currentSubtune;
  @Int32()
  external int sidChips;
  @Int32()
  external int sidModel;
  @Int32()
  external int isNtsc;
  @Int32()
  external int lengthMs;
  @Int32()
  external int system;
}

/// SID model values (cd_sid_model).
enum SidModel { auto, mos6581, mos8580 }

/// The machine a tune was written for (cd_system).
enum TuneSystem {
  c64('C64'),
  atariSt('Atari ST'),
  amiga('Amiga'),
  pc('PC');

  const TuneSystem(this.label);
  final String label;

  static TuneSystem fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : c64;
}

/// Plain Dart copy of a tune's metadata.
class TuneInfo {
  final String title;
  final String author;
  final String released;
  final String format;
  final int subtunes;
  final int startSubtune;
  final int currentSubtune;
  final int sidChips;
  final SidModel sidModel;
  final bool isNtsc;
  final int? lengthMs;
  final TuneSystem system;

  bool get isSid => system == TuneSystem.c64;

  const TuneInfo({
    required this.title,
    required this.author,
    required this.released,
    required this.format,
    required this.subtunes,
    required this.startSubtune,
    required this.currentSubtune,
    required this.sidChips,
    required this.sidModel,
    required this.isNtsc,
    required this.lengthMs,
    required this.system,
  });

  static String _str(Array<Uint8> a) {
    final bytes = <int>[];
    for (var i = 0; i < 64; i++) {
      final b = a[i];
      if (b == 0) break;
      bytes.add(b);
    }
    // PSID strings are ISO-8859-1; HVSC sometimes has UTF-8. Prefer UTF-8.
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  factory TuneInfo.fromStruct(CdInfoStruct s) => TuneInfo(
    title: _str(s.title),
    author: _str(s.author),
    released: _str(s.released),
    format: _str(s.format),
    subtunes: s.subtunes,
    startSubtune: s.startSubtune,
    currentSubtune: s.currentSubtune,
    sidChips: s.sidChips,
    sidModel: SidModel.values[s.sidModel.clamp(0, 2)],
    isNtsc: s.isNtsc != 0,
    lengthMs: s.lengthMs > 0 ? s.lengthMs : null,
    system: TuneSystem.fromIndex(s.system),
  );
}

typedef _VoidPtrFn = Pointer<Void> Function();
typedef _DestroyN = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

/// Low-level access to the chipdeck shared library.
class ChipDeckNative {
  ChipDeckNative._(DynamicLibrary lib)
    : version = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'cd_version',
          )()
          .toDartString(),
      _audioCreate = lib.lookupFunction<Pointer<Void> Function(), _VoidPtrFn>(
        'cd_audio_create',
      ),
      _audioDestroy = lib.lookupFunction<_DestroyN, _DestroyD>(
        'cd_audio_destroy',
      ),
      _audioPlayer = lib
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('cd_audio_player'),
      _audioSetPlaying = lib
          .lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)
          >('cd_audio_set_playing'),
      _audioSetVolume = lib
          .lookupFunction<
            Void Function(Pointer<Void>, Float),
            void Function(Pointer<Void>, double)
          >('cd_audio_set_volume'),
      _audioScope = lib
          .lookupFunction<
            Size Function(Pointer<Void>, Pointer<Int16>, Size),
            int Function(Pointer<Void>, Pointer<Int16>, int)
          >('cd_audio_scope'),
      _lastError = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('cd_last_error'),
      _loadSonglengths = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>)
          >('cd_load_songlengths'),
      _setSidModel = lib
          .lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)
          >('cd_set_sid_model'),
      _loadFile = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32),
            int Function(Pointer<Void>, Pointer<Utf8>, int)
          >('cd_load_file'),
      _selectSubtune = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('cd_select_subtune'),
      _getInfo = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<CdInfoStruct>),
            int Function(Pointer<Void>, Pointer<CdInfoStruct>)
          >('cd_get_info'),
      _positionMs = lib
          .lookupFunction<
            Uint32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cd_position_ms'),
      _sidRegs = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>),
            int Function(Pointer<Void>, int, Pointer<Uint8>)
          >('cd_get_sid_registers'),
      _channelCount = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cd_channel_count'),
      _channelName = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Size),
            int Function(Pointer<Void>, int, Pointer<Utf8>, int)
          >('cd_channel_name'),
      _channelScope = lib
          .lookupFunction<
            Size Function(Pointer<Void>, Pointer<Int16>, Size),
            int Function(Pointer<Void>, Pointer<Int16>, int)
          >('cd_channel_scope'),
      _probe = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<CdInfoStruct>),
            int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<CdInfoStruct>)
          >('cd_probe_file');

  final String version;
  final Pointer<Void> Function() _audioCreate;
  final void Function(Pointer<Void>) _audioDestroy;
  final Pointer<Void> Function(Pointer<Void>) _audioPlayer;
  final void Function(Pointer<Void>, int) _audioSetPlaying;
  final void Function(Pointer<Void>, double) _audioSetVolume;
  final int Function(Pointer<Void>, Pointer<Int16>, int) _audioScope;
  final Pointer<Utf8> Function(Pointer<Void>) _lastError;
  final int Function(Pointer<Void>, Pointer<Utf8>) _loadSonglengths;
  final void Function(Pointer<Void>, int) _setSidModel;
  final int Function(Pointer<Void>, Pointer<Utf8>, int) _loadFile;
  final int Function(Pointer<Void>, int) _selectSubtune;
  final int Function(Pointer<Void>, Pointer<CdInfoStruct>) _getInfo;
  final int Function(Pointer<Void>) _positionMs;
  final int Function(Pointer<Void>, int, Pointer<Uint8>) _sidRegs;
  final int Function(Pointer<Void>) _channelCount;
  final int Function(Pointer<Void>, int, Pointer<Utf8>, int) _channelName;
  final int Function(Pointer<Void>, Pointer<Int16>, int) _channelScope;
  final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<CdInfoStruct>)
  _probe;

  static ChipDeckNative? _instance;

  /// Opens the library once per isolate.
  static ChipDeckNative open() => _instance ??= ChipDeckNative._(_openLib());

  static DynamicLibrary _openLib() {
    if (Platform.isWindows) return DynamicLibrary.open('chipdeck.dll');
    if (Platform.isMacOS) return DynamicLibrary.open('libchipdeck.dylib');
    if (Platform.isLinux) {
      // Flutter Linux bundles put libraries in <exe dir>/lib.
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = '$exeDir/lib/libchipdeck.so';
      if (File(bundled).existsSync()) return DynamicLibrary.open(bundled);
    }
    return DynamicLibrary.open('libchipdeck.so');
  }

  /// Reads metadata without playing. Safe to call from a background isolate.
  TuneInfo? probe(String path, {String? songlengths}) {
    return using((arena) {
      final info = arena<CdInfoStruct>();
      final p = path.toNativeUtf8(allocator: arena);
      final s = songlengths == null || songlengths.isEmpty
          ? nullptr
          : songlengths.toNativeUtf8(allocator: arena);
      if (_probe(p, s.cast(), info) != 0) return null;
      return TuneInfo.fromStruct(info.ref);
    });
  }
}

/// The audio engine: one native player plus the output device.
class ChipDeckEngine {
  ChipDeckEngine._(this._n, this._audio) : _player = _n._audioPlayer(_audio);

  final ChipDeckNative _n;
  final Pointer<Void> _audio;
  final Pointer<Void> _player;
  final Pointer<Int16> _scopeBuf = calloc<Int16>(4096);
  final Pointer<Uint8> _regBuf = calloc<Uint8>(32);
  final Pointer<CdInfoStruct> _infoBuf = calloc<CdInfoStruct>();
  final Pointer<Int16> _chanBuf = calloc<Int16>(maxChannels * 4096);
  final Pointer<Utf8> _nameBuf = calloc<Uint8>(32).cast();
  List<String> _channelNames = const [];

  /// Most channels a tune can have (a 32-channel module); CD_MAX_CHANNELS in C.
  static const maxChannels = 32;

  /// Returns null if no audio device could be opened.
  static ChipDeckEngine? create() {
    final n = ChipDeckNative.open();
    final a = n._audioCreate();
    if (a == nullptr) return null;
    return ChipDeckEngine._(n, a);
  }

  String get version => _n.version;
  String get lastError => _n._lastError(_player).toDartString();

  set playing(bool v) => _n._audioSetPlaying(_audio, v ? 1 : 0);
  set volume(double v) => _n._audioSetVolume(_audio, v);
  set sidModel(SidModel m) => _n._setSidModel(_player, m.index);

  bool loadSonglengths(String path) => using(
    (a) => _n._loadSonglengths(_player, path.toNativeUtf8(allocator: a)) == 0,
  );

  bool load(String path, {int subtune = 0}) {
    _channelNames = const [];
    return using(
      (a) =>
          _n._loadFile(_player, path.toNativeUtf8(allocator: a), subtune) == 0,
    );
  }

  bool selectSubtune(int subtune) => _n._selectSubtune(_player, subtune) == 0;

  TuneInfo? get info => _n._getInfo(_player, _infoBuf) == 0
      ? TuneInfo.fromStruct(_infoBuf.ref)
      : null;

  int get positionMs => _n._positionMs(_player);

  /// Latest output samples, newest last, for an oscilloscope.
  Int16List scope(int frames) {
    final got = _n._audioScope(_audio, _scopeBuf, frames.clamp(0, 4096));
    return Int16List.fromList(_scopeBuf.asTypedList(got));
  }

  /// Names of the tune's channels ("V1".."V3", "Digi", "2:V1"... for SID;
  /// "A", "B", "C", "DAC" for Atari; "1".."4" for an Amiga MOD), empty if
  /// nothing is loaded.
  List<String> get channelNames {
    final n = _n._channelCount(_player).clamp(0, maxChannels);
    if (n != _channelNames.length) {
      _channelNames = [
        for (var i = 0; i < n; i++)
          _n._channelName(_player, i, _nameBuf, 32) == 0
              ? _nameBuf.toDartString()
              : '${i + 1}',
      ];
    }
    return _channelNames;
  }

  /// Latest [frames] samples of every channel (newest last), one list per
  /// channel, in the order of [channelNames].
  List<Int16List> channelScopes(int frames) {
    final n = channelNames.length;
    if (n == 0) return const [];
    frames = frames.clamp(1, 4096);
    final got = _n._channelScope(_player, _chanBuf, frames);
    final all = _chanBuf.asTypedList(n * frames);
    return [
      for (var c = 0; c < n; c++)
        Int16List.fromList(all.sublist(c * frames, c * frames + got)),
    ];
  }

  /// SID registers of chip [chip], or null if unavailable.
  Uint8List? sidRegisters(int chip) => _n._sidRegs(_player, chip, _regBuf) == 0
      ? Uint8List.fromList(_regBuf.asTypedList(32))
      : null;

  void dispose() {
    _n._audioDestroy(_audio);
    calloc.free(_scopeBuf);
    calloc.free(_regBuf);
    calloc.free(_infoBuf);
    calloc.free(_chanBuf);
    calloc.free(_nameBuf);
  }
}
