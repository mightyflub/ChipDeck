# ChipDeck working notes

Chronological log of research and decisions. Newest entries at the bottom.

## 2026-11-04: Evaluation of sakirhossn/SidPlayer

Stephen asked whether https://github.com/sakirhossn/SidPlayer would help.

Findings (cloned at commit 8c3e9f9, 2026-10-18):

- It is a **video** player for Windows ("Premium Local Video Player"), built
  with Electron 33 + React + Vite, using Chromium decoders and FFmpeg.
- It has **no C64 SID code at all**: no 6510 CPU, no SID chip emulation, no
  PSID/RSID parser. "Sid" is just the product name.
- License: package.json says MIT, but there is no LICENSE file in the repo.
- Conclusion: **not useful** for ChipDeck. At most it is an example of an
  Electron UI shell, which we do not plan to use.

## 2026-11-04: SID engine options

- **libsidplayfp** (https://github.com/libsidplayfp/libsidplayfp)
  - GPL-2.0-or-later, C++, actively maintained (latest tag v3.1.2, commits
    in Oct 2026). The engine behind sidplayfp, JSidplay2-adjacent tooling,
    and many other players.
  - Full C64 emulation (6510 CPU, CIA, VIC timing, PLA), plays PSID and RSID,
    including digi tunes. Ships two SID emulations: **reSIDfp** (most
    accurate, recommended default) and classic reSID.
  - Supports 6581/8580 models, multi-SID (2SID/3SID), Songlengths.md5
    database lookup, STIL (via libstilview).
  - Optional: KERNAL/BASIC/chargen ROMs improve RSID compatibility; open
    replacement ROMs exist, so we do not need to ship Commodore ROMs.
  - Builds with autotools upstream; we will add our own CMake build of the
    sources so it compiles cleanly with MSVC and the Android NDK.
- **Alternatives considered**: websid / tinyrsid (JS/C, good but less
  accurate on some edge cases), libsidplay2 (abandoned), writing our own
  (months of work for a worse result). Rejected in favour of libsidplayfp.

**License consequence:** linking libsidplayfp makes ChipDeck a GPL-2.0+ work
when distributed. Fine for an open-source hobby player; ChipDeck should
adopt GPL-2.0-or-later (or GPL-3.0) itself.

## 2026-11-04: SNDH (later)

- **psgplay** (https://github.com/frno7/psgplay, GPL-2.0, C): Atari ST
  emulation (68000 + YM2149 + timers) designed for SNDH. Good candidate.
- **sc68** is the other mature option (older, harder to build).
- Decision deferred until SID playback works.

## 2026-11-04: Proposed stack (approved same day)

- `core/`: C++17 library "chipdeck-core" with a small C API
  (`cd_open(file)`, `cd_render(buf, frames)`, `cd_set_subtune(n)`,
  `cd_info()`). Wraps libsidplayfp now, psgplay later. Same code on Windows
  and Android.
- Audio output: **miniaudio** (single header, public domain / MIT-0) uses
  WASAPI on Windows and AAudio/OpenSL on Android.
- Build: CMake. Windows: Visual Studio 2022 (MSVC) or MinGW.
- Step 1 UI: a command-line player (`chipdeck-cli tune.sid [subtune]`) to
  prove playback on Windows quickly.
- Step 2 UI: one cross-platform UI. Recommended **Flutter** (Windows +
  Android from one codebase, calls the C core via dart:ffi). Alternative:
  Qt 6/QML (C++ throughout, heavier Android tooling).

## 2026-11-04: Stack approved, milestone 1 (CLI player) built

Stephen picked "build CLI, Flutter UI later".

What was done:
- Vendored libsidplayfp 3.1.2 and libresidfp 1.2.3 from their **release
  tarballs** (not git): the tarballs include the pre-assembled 6502 driver
  `.bin` files, so we avoid needing the xa65 assembler. Note that since
  libsidplayfp 3.0, reSIDfp lives in a separate repo (libresidfp).
- Wrote `third_party/CMakeLists.txt` replacing autotools. Gotchas found:
  - libsidplayfp's `sidcxx11.h` relies on `config.h` defining `HAVE_CXX17`
    etc.; we define `HAVE_CXX17` publicly instead.
  - MSVC needs `/Zc:__cplusplus` or reSIDfp thinks it is not C++11.
  - `sidplayfp::getBufSize()` returns a count of **samples (int16)**, not
    bytes as its doc comment says, and it was too small in practice. The
    core sizes the mix buffer as `play()` result * 2 instead (found with
    AddressSanitizer: heap overflow in SimpleMixer::doMix).
- Wrote `chipdeck-core` (C API) and `chipdeck-cli`.
- HVSC mirrors are blocked from the cloud dev container, so we wrote our
  own tiny PSID test tune (`tools/make_test_sid.py`, 2 subtunes, pulse
  wave). Tests check audio level, subtune switching (pitch doubles), load
  from memory, and error handling.
- Performance: 120 s of audio renders in ~15 s on one container core in
  Release (~8x real time) with RESAMPLE_INTERPOLATE at 48 kHz.
- Verified: Linux build + tests (also under ASan), MinGW cross-compiled
  Windows exe builds. MSVC build is checked in GitHub Actions.

## 2026-11-04: Confirmed on Windows

Stephen ran the MinGW-built chipdeck-cli.exe on his PC: "runs well".

## 2026-11-04: Flutter app (milestone 2)

Stephen asked to start the Flutter app: "attractive but functional".

- Core grew a shared library (`chipdeck-shared` target, file chipdeck.dll /
  libchipdeck.so) with `cd_audio_*` (miniaudio output, volume, scope ring
  buffer), `cd_get_sid_registers` (for voice meters) and `cd_probe_file`
  (metadata for lists; caches the Songlengths DB across calls).
- Target had to be renamed from `chipdeck` because Flutter's runner
  executable target is also called `chipdeck` (CMP0002 clash).
- The app runner CMakeLists (`app/windows`, `app/linux`) add the repo root
  as a subdirectory and bundle the library via PLUGIN_BUNDLED_LIBRARIES.
- Linux loads `<exe dir>/lib/libchipdeck.so` explicitly; Windows loads
  `chipdeck.dll` from the exe folder.
- Probing and folder scans run in `Isolate.run` with top-level functions
  (closures in instance methods can capture `this`, which cannot be sent).
- Flutter cannot build Windows apps from Linux, so the Windows app build
  is only checked in CI. Linux build tested in the container under Xvfb
  (no sound card; miniaudio falls back to its null device, which still
  drives the render callback, so the scope works).
- SID voice meter: from register writes only (gate, sustain level,
  waveform, frequency -> note name). Real envelope output is not exposed
  by libsidplayfp's getSidStatus.

## 2026-11-04: SNDH and YM engine evaluation

Stephen linked https://github.com/arnaud-carre/sndh-player and asked for a
plan (no code yet) for .sndh and .ym support. Full plan:
[SNDH_YM_PLAN.md](SNDH_YM_PLAN.md).

- **sndh-player** (v1.23, MIT, commit 770fc0c on 2026-11-04) is an ImGui/GLFW
  desktop app for Windows and macOS. Its emulation lives in the
  **AtariAudio** submodule (https://github.com/arnaud-carre/AtariAudio,
  v1.27, MIT, commit f68f058 on 2026-10-29). The app itself is not reusable
  as a library, but AtariAudio is designed to be.
- **AtariAudio**: plays SNDH (ICE packed too, STE DAC, blitter) and all YM
  variants (YM2 to YM6, MIX1, YMT1/2, LZH packed). C++17, ~14 source files,
  no dependencies, no file I/O, no float, thread safe per instance, plain
  CMake. Grepped sources: no OS headers, intrinsics or MSVC-only code, so
  MSVC and Android NDK builds should be straightforward. Output is mono
  16-bit at any sample rate. Used by BZR Player 2 and rePlayer.
- **psgplay** (GPL-2.0, C): SNDH only, GNU make and GCC extensions, would need
  a CMake/MSVC port plus our own ICE depacker. Kept as a fallback only.
- **StSound** (MIT): deprecated by its author in favour of AtariAudio.
- **ayumi** (MIT): AY/YM chip core only, no file formats or 68000. Useful
  later for ZX Spectrum AY formats, not for SNDH/YM.
- **Decision (proposed)**: AtariAudio for both SNDH and YM, replacing psgplay
  in the earlier stack. Core gets a `Backend` interface + magic-byte probe so
  SID and Atari backends sit side by side.
- Could not compile-test AtariAudio in this session (building third-party
  code was blocked in the cloud sandbox). First coding step should build it
  with MSVC and the NDK.

## 2026-11-04: SNDH and YM playback in core and CLI

Stephen asked for "a command line player test like we did for the sid files".

- Vendored AtariAudio 1.27 (`third_party/atariaudio`, tag 1.27 = commit
  f68f058) and added a CMake target `atariaudio`. Builds with no warnings
  to fix on GCC 13 and MinGW-w64 13; MSVC is covered by CI.
- `core/src/atari_backend.{h,cpp}`: `isAtariTune()` (same magic checks as
  AtariAudio's own QuickFileTypeCheck) and `AtariTune` (load, subtunes,
  length, mono to stereo, position). `chipdeck.cpp` dispatches to it in
  every C API call; the SID code is unchanged. `cd_info` layout is
  unchanged because the Flutter app maps it with dart:ffi.
- Our own test tunes (`tools/make_test_atari.py`): an SNDH with a
  hand-assembled 68000 driver (2 subtunes, ~492 Hz and ~984 Hz square
  waves, FRMS lengths 20 s and 30 s) and a 10 s YM5 file. Rendering them
  gives exactly the expected pitches, which also proves the 68000, YM
  ports and SNDH header parsing work.
- Lengths: SNDH "50 Hz" ticks are the real ST VBL rate (~50.05 Hz), so
  1000 ticks = 19958 ms, not 20000. Tests allow 100 ms.
- Sanitizers: ASan clean. GCC UBSan `bounds` reports an out-of-range index
  at `m68k.cpp:55` (the opcode jump table). In gdb the opcode (REG_IR) is
  0x6000, which is valid, so this is a false report about the
  pointer-to-member array, not a real bug. Clang's sanitizer runtime is
  not installed in the container, so this could not be cross-checked there.
- Could not run the Windows .exe in the container (no Wine); MinGW build
  links fine and CI runs the tests with MSVC.

## 2026-11-04: App plays SNDH/YM too

Merged the SNDH/YM thread (PR #1) into this branch. The app accepts
.sndh/.snd/.ym, shows an "Atari ST" badge and hides the SID voice tiles
when `sid_chips == 0` (scope only). SNDH files carry their own length.

## 2026-11-04: Music library and search index

Stephen: "store locations of my music archive and let me browse and search
them ... we need that and a search index".

- Index format: one JSON file (`library.json`, app support dir) with roots,
  last scan time and a compact array per track
  `[path, title, author, released, format, subtunes, lengthMs, size, mtime, sidChips]`.
  Chosen over SQLite to avoid another native dependency; HVSC (~60k tunes)
  is roughly 8-10 MB of JSON and loads in an isolate.
- Search is an in-memory linear scan over a lowercased blob per track
  (title, author, released, file and folder name); all words must match.
  Fast enough for HVSC size (milliseconds). If it gets slow, add a token
  index or move to SQLite FTS5.
- Indexer runs in a spawned isolate, reports progress every 250 files,
  reuses entries whose size+mtime are unchanged, and hands results back
  with Isolate.exit (no copy).
- Tested with a generated fake archive of 2642 files (HVSC-like folders);
  indexed in a few seconds in the container.

## 2026-11-04: Android app

Stephen: "build an android version of this app. Going forward we'll keep
the two versions in sync". So one Flutter codebase and one native core for
both; platform code is kept small and behind `app/lib/platform/`.

- Native: `app/android/app/build.gradle.kts` uses `externalNativeBuild`
  with the repo root CMakeLists (`CHIPDECK_BUILD_CLI/TESTS=OFF`, target
  `chipdeck-shared`, static libc++). Dart loads `libchipdeck.so` by name,
  which already worked in `chipdeck_ffi.dart`. miniaudio picks AAudio,
  falling back to OpenSL ES (third_party links OpenSLES and log on Android).
- Storage, options considered:
  1. Pure SAF (content:// tree URIs everywhere): would need a native
     directory walker and an fd/memory based load path for the core and the
     index, and a different code path from Windows. Slow for HVSC's ~60k
     files (SAF queries are IPC calls).
  2. **Chosen: "All files access" (MANAGE_EXTERNAL_STORAGE) + SAF pickers
     mapped back to paths.** The library, playlist and Songlengths code stay
     identical to Windows (dart:io paths). Fine for a sideloaded APK. Google
     Play only allows this permission for some app types, so a Play release
     would need option 1 or a review exception (noted in HANDOVER).
  Tree/document IDs from `com.android.externalstorage.documents`
  (`primary:Music/HVSC`, `1A2B-3C4D:...` for SD cards, `home:` for
  Documents) map to `/storage/emulated/0/...` or `/storage/<volume>/...`.
  Download provider `raw:` IDs are paths too. Anything else (Drive, Downloads
  `msf:` IDs) is copied to `files/imported/`. Folders that do not map get a
  clear error.
- Background playback: the audio thread is native, so it keeps running when
  the activity is hidden, but Android would kill the process. A
  `mediaPlayback` foreground service (`PlaybackService.kt`) runs while a tune
  plays, with a MediaStyle notification and a MediaSessionCompat (lock
  screen, headset and Bluetooth buttons). Paused: the service leaves the
  foreground but keeps the notification. Dart drives it through
  `lib/platform/android_media.dart`, only sending changes (the player
  notifies every 200 ms).
- Back on the root screen calls `moveTaskToBack` (FlutterActivity
  `popSystemNavigator`), so back does not stop the music. Swiping the app
  away from recents or finishing the activity ends the process, because the
  native audio device would otherwise outlive the Flutter engine.
- Library fix (both platforms): roots that cannot be listed keep their old
  entries instead of being emptied (matters for revoked permission or a
  removed SD card; same for an offline network drive on Windows).
- Signing: committing a keystore was refused as a credential leak, so CI
  signs with a key from repository secrets when they exist and otherwise
  with a per-run debug key (then each new APK needs an uninstall first).
- Not verifiable in the container: the Android SDK/NDK hosts
  (dl.google.com) are blocked, so the APK is built only in CI.

## 2026-11-04: Landscape layout (Ayn Thor)

Stephen tried the APK on his Ayn Thor: it works (library, SID playback in
the background), but search showed hardly any results on the landscape top
screen, and he asked for the whole UI to suit landscape. At ~731x411 dp
the old phone layout spent ~330 dp on chrome (title bar, library header,
search box, filter chips, results header, bottom bar), leaving room for
about one result. Now (same code on all platforms, by window size):
side rail instead of title and bottom bars, single-row toolbars, 40 dp
one-line rows with columns, and a two-column Now playing that fits without
scrolling. Search shows 9 rows at 731x411 instead of ~1. Wide desktop and
portrait layouts are unchanged (checked with screenshots under Xvfb using
the new CHIPDECK_WINDOW size override in the Linux runner).

## 2026-11-04: Second-screen controls

Stephen asked for dual-screen support on the Ayn Thor: player controls on
the bottom screen, everything else on top. Android exposes the second
display through DisplayManager, so ChipDeck shows an Android Presentation
there whenever a display other than its own is on. The controls are
Flutter too, in a second engine from a FlutterEngineGroup (cheap: it
shares the code and assets with the main engine) with its own entrypoint,
`controlsMain`. The second engine has no player of its own: the main engine
sends a small state map (title, position, subtunes, volume, advance mode,
playlist position) on every player change, and the controls send actions
back; Kotlin only relays. While the controls are showing, the main screen
hides its transport and subtune buttons to give the library more room.
Untested on hardware: the Thor may not report its bottom screen as a
presentation display, which is why any non-own display is used as a
fallback. A setting turns it off.

First try on the Ayn Thor: the controls appeared on the bottom screen but
said "Nothing playing", and the top screen kept its own transport. Cause:
Android puts the controls up while the main Dart code is still starting
(loading the player and library), so the "secondScreen" message arrived
before Dart listened. Flutter keeps only one unheard message per channel,
and the controls' "ready" pushed it out. Dart now asks
"secondScreenShowing" once it listens.

Second try (0.4.0-test.52): the controls work, but going to the background
or closing ChipDeck changed only one screen, and Android could then reopen
ChipDeck on the bottom screen with the controls on top, with no way to get
both back. Now the controls come down when the activity stops and go up
again when it starts, only when ChipDeck is on the main display, and their
window is not focusable (touch still works).

Third try (0.4.0-test.54): better, but the bottom screen "tends to lose
focus" with no easy way back (most likely another app or the launcher
covering the controls there). Added a button on the main screen that puts
the controls back in front, and ChipDeck now does that by itself when it
becomes the top app again (onTopResumedActivityChanged, Android 10+).

## 2026-11-04: Version numbers

Stephen asked for version numbers on every build, test builds included.
Base version in pubspec (now 0.4.0: CLI, Windows app, library, Android
were the first four milestones); CI adds `-test.<run>` unless the build is
from a matching `v` tag. Shown in Settings and in artifact and APK names.
He then said a Windows test build isn't needed every time: the Windows
app now builds only on main, tags and on request, and branch pushes no
longer make a second run next to the pull request's.


## 2026-11-04: Every channel in the visualiser (0.5.0)

Stephen asked for the visualiser to show all channels of a tune,
including digi drums on SID files. The Now playing visualiser now shows
one oscilloscope per channel by default ("Channels"); the corner button
switches back to the old mixed scope with SID voice tiles ("Mix"), and
the choice is remembered (`channelScopes` preference).

Channels per format:
- SID: V1, V2, V3 and Digi per chip (2SID/3SID tunes get "2:V1" etc.,
  up to 12 channels). V1-V3 are each voice's output (waveform x envelope)
  before the filter and master volume, so filtered voices still show
  clearly. Digi is the $D418 master volume nibble as a waveform: that is
  where volume-register digis and drums (the classic 4-bit sample
  technique, Mahoney's and others' variants) are heard. Digis that use
  pulse width or the test bit play through a voice and show on that
  voice's scope instead. Tiles also show each voice's note and waveform.
- SNDH: YM2149 channels A, B, C and the STE DAC. YM: A, B, C (MIX1/YMT
  files: one "Samples" channel). YM5/6 digidrums play through a YM
  channel and show there.

How: 
- reSIDfp (patched, see third_party/README.md) records each voice's
  output and the volume nibble whenever it produces an output sample,
  into a 4-values-per-sample buffer next to the normal one;
  libsidplayfp exposes it as `sidplayfp::voiceBuffers()`.
- AtariAudio already had `AudioRenderWithVisualInfos` (one signed byte
  per channel per sample, made for per-voice scopes); the core uses it.
- The core keeps a 4096-sample ring per channel, filled as `cd_render`
  hands out audio (so it matches what is heard, like the mixed scope),
  with a ~4 Hz DC blocker so silent channels and the steady volume of
  non-digi tunes sit at zero. New C API: `cd_channel_count`,
  `cd_channel_name`, `cd_channel_scope`.
- The app reads 2048 samples per channel each frame, triggers each scope
  on a rising zero crossing and scales it with a slowly falling peak
  (auto gain), so quiet channels are still visible.

Tests: core_test checks the test tune shows on V1 only, and a tiny
PSID built in the test that flips $D418 every frame shows on Digi only;
atari_test checks the SNDH plays on channel A only and YM has 3 channels.
Clean under AddressSanitizer. Screenshots:
docs/screenshots/landscape-channels-sid.png (made-up 3-voice tune with a
slow volume flip on Digi) and landscape-channels-sndh.png.

Not tested on real digi tunes in the cloud (HVSC is blocked here); worth
checking with e.g. a Mahoney or Galway digi tune on Stephen's devices.

Stephen tried 0.5.0-test.61 on the Ayn Thor: "that works."

## 2026-11-04: Amiga MOD and Fasttracker 2 XM (0.6.0)

Stephen asked for the Amiga .mod format, then also Fasttracker 2 .xm.

Engine choice: **libxmp 4.6.3** (MIT, plain C, vendored in
third_party/libxmp from the libxmp-4.6.3 git tag). Compared with libopenmpt
(BSD, C++17, larger, more accurate on IT/MPTM): libxmp is smaller, builds
everywhere with no dependencies, has an Amiga 500 "Paula" mixer
(XMP_FLAGS_A500: BLEP output plus the LED filter, as on the real machine)
and reports hidden subsongs ("sequences") with durations at load time, so
the library gets lengths and subtune counts without rendering. It also
loads PowerPacker/zip/gz/lha-packed modules and ProWizard-packed Amiga
formats when given a file. Both formats are covered by the same engine.

How it plugs in (core/src/mod_backend.cpp, `chipdeck::ModTune`):
- Detection order in `cd_load_file`/`cd_probe_file`: Atari magic, then
  PSID/RSID magic, then (unless the extension is a C64 one without magic:
  .prg .p00 .mus .str .c64) libxmp, then libsidplayfp as before. The C64
  extension check stops libxmp's guessing Soundtracker loader from claiming
  a .prg.
- Files are opened by ChipDeck (UTF-8 paths on Windows) and handed to
  `xmp_load_module_from_file`, which unpacks in memory and never runs
  external tools (the unrar/unmo3 helpers need a file name, which we never
  pass). `cd_load_memory` uses `xmp_load_module_from_memory` (no unpacking).
- Subtunes are libxmp sequences; length_ms is the sequence duration.
  Playback loops forever like SID/Atari; the app advances by length.
- New `cd_info.system` (appended at the end of the struct; Dart maps it):
  C64 0, Atari ST 1, Amiga 2, PC 3. XM files are "PC" (libxmp names their
  type "<tracker> XM <version>"), all other modules "Amiga".
- Per-channel scopes: a "ChipDeck patch" in libxmp's mixer.c records how
  much each voice adds to the mix buffer in every tick (buffer before and
  after mixing that voice), summed per tracker channel (the voice's root
  channel, so FT2 fade-out voices count for their channel). Read with
  `xmp_chipdeck_read_tap` after each `xmp_play_frame`. Channels are named
  "1".."N"; CD_MAX_CHANNELS went from 12 to 32 (XM allows 32).
- Mixer: Paula for Amiga modules, cubic spline interpolation for the rest,
  libxmp's default 70% stereo separation (Amiga hard-panning is tiring on
  headphones).

App: .mod and .xm in the pickers and library scan, plus the Amiga habit of
a "mod." prefix ("mod.axelf") when scanning folders; library badge MOD/XM
in green; a "MOD" filter (tracker modules) next to C64/ST; now playing
shows "Amiga" or "PC" and the channel count; second-screen controls show
the system. Visualiser: tracker channels cycle violet/cyan/pink/green, rows
of 8 above 12 channels, and a narrow window drops to a column count that
divides the channels evenly (6 -> 3 x 2). Library indexes from before
0.6.0 load fine (sidChips 0 is read as Atari) and pick up modules on the
next rescan.

Tests: tests/mod_test.cpp with our own tunes from tools/make_test_mod.py
(4-channel M.K. with a hidden second sequence) and tools/make_test_xm.py
(6 channels, channel 6 starts late): metadata, subtunes, channel
separation, memory loading, switching back to SID. Clean under
AddressSanitizer. Linux app checked under Xvfb (6-channel XM and the
731x411 landscape layout with a 4-channel MOD): docs/screenshots/
channels-xm.png and landscape-channels-mod.png.

Not tested in the cloud: real MOD/XM collections (Modland/AMP are not
reachable here). Worth trying on Stephen's devices: a classic Protracker
MOD, an 8-channel MOD, a big XM (20+ channels), and a PowerPacked mod.
