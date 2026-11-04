# ChipDeck handover

Read this first. It is the single source of truth for picking up the work.
Detailed history and research live in [NOTES.md](NOTES.md).

## Goal

ChipDeck is a retro chiptune player for **Windows and Android**. First
target: play C64 **.sid** files on Windows. Also Atari ST **.sndh** and
**.ym** (done in the core and CLI). Later: Android, possibly more chip formats.

## Keeping Windows and Android in sync

Stephen's rule (2026-11-04): every feature or fix lands on both Windows and
Android, or is listed under "Pending on one platform" below. Both apps are
the same Flutter code (`app/lib`) and the same native core; platform code
lives only in `app/lib/platform/` (Dart) and `app/android/.../kotlin`
(Android glue). Prefer shared Dart code; branch on `Platform.isAndroid`
only inside `lib/platform/`.

### Pending on one platform

- Android only: background playback notification, lock screen/headset
  controls, pause on headphone unplug (Windows has no equivalent need yet;
  SMTC media keys on Windows would be the counterpart).
- Android only: player controls on a second screen (dual-screen devices
  such as the Ayn Thor). Windows could do the same on a second monitor
  with a second window; not planned unless asked.
- Windows only: keyboard shortcuts (harmless on Android; work with a
  Bluetooth keyboard).

## Current state (2026-11-04)

- **Android app (branch claude/project-thread-ryqtet, PR #3):** same Flutter
  app and core as Windows, built as an APK in CI (`app-android` job,
  artifact `chipdeck-app-android` containing `ChipDeck.apk`). Not yet tried
  on a phone. See "The Android app" below.

- **Milestone 1 done, confirmed working on Stephen's Windows PC:** a
  command-line player `chipdeck-cli` that plays .sid files through the
  speakers or renders them to WAV.
- **Milestone 2 in progress: Flutter GUI (`app/`).** Builds and runs on
  Linux (screenshots in `docs/screenshots/`). Windows build runs in CI
  (`app-windows` job, artifact `chipdeck-app-windows-x64`); waiting for
  Stephen to try it. Stephen asked for an "attractive but functional"
  interface.
- `chipdeck-core` has a plain C API (`core/include/chipdeck/chipdeck.h`)
  wrapping libsidplayfp 3.1.2 + reSIDfp 1.2.3. It is also built as a
  shared library (`chipdeck.dll` / `libchipdeck.so`, CMake target
  `chipdeck-shared`) that includes audio output (miniaudio) for the app.
- **SNDH/YM playback done in the core and CLI (branch
  claude/project-thread-lu47hk, 2026-11-04):** chipdeck-core plays Atari
  ST .sndh and .ym files through vendored AtariAudio 1.27, behind the same
  C API (`cd_load_*`, `cd_get_info`, `cd_render`, subtunes, `cd_probe_file`).
  The shared library and so the Flutter app pick it up automatically, and
  the app accepts .sndh/.snd/.ym. The CLI build was confirmed working on
  Stephen's Windows PC (2026-11-04). Plan and engine
  comparison: [SNDH_YM_PLAN.md](SNDH_YM_PLAN.md).
- The SNDH/YM thread owns `core/src/chipdeck.cpp` and `atari_backend.*`;
  coordinate before editing those files.
- Unit tests pass on Linux (also under AddressSanitizer). HVSC download
  hosts are blocked from the cloud dev container, so real-tune testing
  happens on Stephen's PC.

## Repository layout

```
CMakeLists.txt            top-level build (core, cli, tests)
core/include/chipdeck/    public C API (chipdeck.h)
core/src/                 implementation: chipdeck.cpp (C API + SID via libsidplayfp),
                          atari_backend.cpp (SNDH/YM via AtariAudio), chipdeck_audio.cpp (output)
app/                      Flutter GUI (lib/native FFI, lib/player state, lib/ui widgets,
                          lib/platform pickers + Android media bridge)
app/android/              Android project: Gradle builds libchipdeck.so from the root
                          CMakeLists; MainActivity.kt (storage, pickers), PlaybackService.kt
cli/main.cpp              chipdeck-cli (miniaudio output, WAV export, keys)
tests/core_test.cpp       SID core tests, run with ctest
tests/atari_test.cpp      SNDH/YM core tests
tests/data/               chipdeck-test.sid/.sndh/.ym (our own public-domain tunes)
tools/make_test_sid.py    regenerates the SID test tune
tools/make_test_atari.py  regenerates the SNDH (hand-assembled 68000) and YM test tunes
third_party/              vendored libsidplayfp, libresidfp, AtariAudio, miniaudio + CMake build
cmake/                    toolchain file for MinGW cross-compile
.github/workflows/        CI: Windows (MSVC) + Linux
docs/                     HANDOVER.md (this), NOTES.md (log)
```

## Architecture

```
+-------------------+      +--------------------------------+
| UI                |      | chipdeck-core (C++17, C API)   |
| now: chipdeck-cli | ---> |  - libsidplayfp + reSIDfp (SID)|
| next: Flutter     | FFI  |  - AtariAudio (SNDH + YM)      |
|   (Win+Android)   |      |                                |
+-------------------+      +--------------------------------+
         |
         v
    miniaudio (WASAPI on Windows, AAudio/OpenSL on Android)
```

- The core only produces PCM (int16 stereo, 48 kHz in the CLI); the app
  owns the audio device. Every core call is mutex-locked so `cd_render()`
  can run on the audio thread while the UI changes subtunes.
- Format choice: `cd_load_file/memory` and `cd_probe_file` check magic
  bytes (`chipdeck::isAtariTune`); Atari tunes go to `chipdeck::AtariTune`
  (`core/src/atari_backend.cpp`), everything else to libsidplayfp. For
  Atari tunes `cd_info.sid_chips` is 0 (use it to tell the kinds apart),
  `format` is "SNDH", "YM 5", "YM 6" etc., `released` is the year, and
  `cd_get_sid_registers` returns 1. AtariAudio output is mono; the core
  copies it to both channels.
- File paths are UTF-8 everywhere; on Windows the core converts to UTF-16
  before opening files, so non-ASCII folder names work.

## Key decisions

| Decision | Choice | Why |
| --- | --- | --- |
| SID emulation | libsidplayfp 3.1.2 with reSIDfp | Most accurate open engine, maintained, portable C++ |
| How it is included | Vendored release tarball sources + our own CMake | No xa65/autotools needed; builds with MSVC, MinGW and NDK |
| Audio output | miniaudio 0.11.26 | One file, WASAPI on Windows, AAudio on Android |
| Build system | CMake >= 3.16 | Works with Visual Studio and the Android NDK |
| License | GPL-2.0-or-later (LICENSE) | Required by libsidplayfp |
| UI | CLI for testing, Flutter app for users | Approved by Stephen 2026-11-04 |
| App audio | Native: miniaudio inside chipdeck.dll | No Flutter audio plugin needed; same code on Android |
| App <-> core | dart:ffi to a C API, metadata probing in a background isolate | Simple, no platform channels |
| App look | Dark theme, violet accent (#8E7CFF), cyan phosphor scope | Retro feel, readable |
| SNDH + YM emulation | AtariAudio 1.27 (vendored, MIT) | One small dependency-free library for both formats; see SNDH_YM_PLAN.md |
| Sampling | 48 kHz, RESAMPLE_INTERPOLATE | Best quality; ~8x real time on one core, fine for playback |
| Android file access | "All files access" + SAF pickers mapped to paths | Library/index code identical to Windows; fast on HVSC. Not Play Store friendly (see NOTES.md) |
| Android background audio | Foreground service + MediaSessionCompat (androidx.media) | Survives screen off; lock screen and headset controls |
| Android signing | Key from repo secrets in CI, debug key otherwise | Committing a key was refused as a credential leak |

## How to build and run

### Windows (Visual Studio 2022)

Needs Visual Studio 2022 or newer with "Desktop development with C++" (includes CMake).
CMake picks the newest installed Visual Studio automatically.
From a "Developer PowerShell for VS 2022":

```
git clone https://github.com/mightyflub/ChipDeck
cd ChipDeck
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release
build\Release\chipdeck-cli.exe path\to\tune.sid
```

Or download `chipdeck-cli-windows-x64` from the latest GitHub Actions run.

### The Flutter app

Needs Flutter (stable, 3.47 or newer). On Windows also Visual Studio with
"Desktop development with C++".

```
cd app
flutter pub get
flutter run -d windows                 # development
flutter build windows --release        # -> app\build\windows\x64\runner\Release\chipdeck.exe
```

On Linux: `sudo apt install ninja-build libgtk-3-dev clang`, then
`flutter build linux --release`. The runner CMakeLists files include the
repo root CMakeLists, so the native library is built automatically.

Library (added 2026-11-04 at Stephen's request): saved music locations
(e.g. HVSC C64Music, the SNDH archive), indexed in the background into
`library.json` in the app support folder (Windows: %APPDATA%\io.github.mightyflub\chipdeck).
Rescans are incremental (size + mtime), run on startup and via the refresh
button; "Rebuild index" in Music locations re-reads everything. Folder
browser with breadcrumbs and per-folder tune counts, play/add a whole
folder, instant search (all words must match title, composer, released or
folder) with a C64/Atari filter. If a location contains
DOCUMENTS/Songlengths.md5 it is picked up automatically.
Code: `app/lib/library/library.dart`, `app/lib/ui/library_panel.dart`.

Layouts (shared by every platform, chosen by window size in
`home_page.dart`): wide (>= 860 dp: side panel + now playing), portrait
phone (bottom bar), and short landscape (< 560 dp high, e.g. Ayn Thor top
screen ~731x411 dp): a side rail with play/pause and next instead of the
title and bottom bars, one-row toolbars in Library and Playlist, one-line
list rows with columns (title, composer, year, folder, length, subtunes)
whenever a list is >= 560 dp wide, and a two-column Now playing (details
and controls left, scope and voices right). To check a layout on Linux:
`CHIPDECK_WINDOW=731x411 build/linux/x64/release/bundle/chipdeck`.
Screenshots: docs/screenshots/landscape-*.png.

Second screen (Android): when the device has another display (Ayn Thor's
bottom screen, an external monitor), the player controls move there
(`lib/ui/controls_screen.dart`, screenshot
docs/screenshots/second-screen-controls.png) and the main screen drops its
transport and subtune buttons. The controls are a second Flutter engine
(`controlsMain()` in `lib/main.dart`) shown in an Android `Presentation`
by `SecondScreen.kt`; state and actions go through MainActivity
(`controlsState` / `controlsAction`, see `lib/platform/remote_controls.dart`
and `android_media.dart`). Setting: "Controls on second screen" (on by
default). The controls show only while ChipDeck is in the foreground and
on the main display (in the background the notification has the controls),
and their window never takes key focus, so the handheld's buttons stay with
the main screen. Working on the Ayn Thor since 0.4.0-test.52.

App features: playlist (files or whole folders, searchable, remembered
between runs), now playing (title, author, released, PSID/RSID, 6581/8580,
PAL/NTSC, 2SID/3SID), oscilloscope, per-voice activity (waveform, note,
level), progress with Songlengths support, transport, subtune picker,
volume, auto-advance modes (all subtunes then next, next tune, repeat),
shuffle, settings (SID model, Songlengths.md5, default length).
Keys: Space play/pause, Left/Right subtune, N/P tune, +/- volume.

### The Android app

Easiest: download `chipdeck-app-android` from the latest GitHub Actions run
(Actions tab, newest "build" run, Artifacts), unzip, copy `ChipDeck.apk` to
the phone and open it (allow "install unknown apps" for the file manager or
browser). On first use of "Add location" / "Add files" ChipDeck explains and
opens Android's "All files access" screen; switch it on and come back.
Library locations are picked with the system folder picker; internal
storage and SD cards work, cloud folders do not (single files from Drive
etc. are copied into the app).

Signing: the secrets below were set up on 2026-11-04 (Stephen keeps
chipdeck.jks, alias chipdeck), so CI APKs from then on install as updates.
The quick `android-signing-check` CI job shows whether the secrets arrive
and unlock the key. Without secrets, CI signs with a throwaway debug key, so a newer
APK only installs after uninstalling the old one (which clears the library
and settings). To get in-place updates, create a key once and add two
repository secrets (Settings > Secrets and variables > Actions):

```
keytool -genkeypair -keystore chipdeck.jks -alias chipdeck -keyalg RSA -keysize 2048 -validity 20000
# ANDROID_KEYSTORE_BASE64  = base64 of chipdeck.jks (PowerShell: [Convert]::ToBase64String([IO.File]::ReadAllBytes("chipdeck.jks")))
# ANDROID_KEYSTORE_PASSWORD = the password (use the same for store and key)
```

Keep chipdeck.jks safe; it is needed for every future update.
Local build: Flutter + Android Studio (SDK, NDK, CMake from SDK Manager),
then `cd app && flutter build apk --release` (or `flutter run` with a phone
attached). Optional `app/android/key.properties` (storeFile, storePassword,
keyAlias, keyPassword) for release signing; it is git-ignored.

### Linux

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
ctest --test-dir build && ./build/chipdeck-cli tune.sid
```

### Cross-compile a Windows .exe from Linux

```
sudo apt install g++-mingw-w64-x86-64-posix
cmake -S . -B build-win -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
cmake --build build-win -j
```

### Using chipdeck-cli

```
chipdeck-cli tune.sid                 play default subtune
chipdeck-cli -s 3 tune.sid            start at subtune 3
chipdeck-cli -m 8580 tune.sid         force 8580 SID
chipdeck-cli -l Songlengths.md5 x.sid stop at the HVSC song length
chipdeck-cli -t 30 -w out.wav x.sid   render 30 s to WAV
chipdeck-cli -i tune.sid              show info only
chipdeck-cli tune.sndh                Atari ST SNDH (same options; -m is SID only)
chipdeck-cli -s 2 tune.sndh           SNDH subtune 2
chipdeck-cli tune.ym                  Atari ST YM (packed or not)
keys: n/p next/prev subtune, space pause, q quit
```

Songlengths.md5 is in HVSC at `C64Music/DOCUMENTS/Songlengths.md5`.
SNDH/YM lengths come from the file itself (SNDH FRMS/TIME tags, AtariAudio's
built-in timedb, YM frame count); a few SNDH files have none and play forever.
Real SNDH/YM tunes: https://sndh.atari.org/download.php (zip of the archive).

## Known limitations

- Android: no audio focus handling yet (ChipDeck keeps playing over other
  apps and calls; headphone unplug does pause). Back button does not go up
  a library folder (use the breadcrumbs). Cloud folders (Drive etc.) cannot
  be library locations. "All files access" would block a Google Play
  release (see NOTES.md, 2026-11-04 Android). Default Flutter launcher icon.

- No KERNAL/BASIC ROMs bundled. Most tunes play fine; a few RSID tunes need
  them (`--kernal/--basic/--chargen`). Commodore ROMs are copyrighted, so
  we should ship open replacement ROMs or let users point to their own.
- Only .sid (PSID/RSID) tested. libsidplayfp also loads .prg/.p00/.mus.
- SNDH/YM: confirmed working on Stephen's Windows PC (2026-11-04). No
  seeking yet. Mono output (as on the ST's YM chip; STE DAC stereo is folded
  to mono by AtariAudio). AtariAudio's SNDH header parser trusts the header
  size, so a truncated file could read past its buffer; fine for real
  archive files, worth hardening before loading untrusted downloads.
- GCC's `-fsanitize=undefined` (the `bounds` check) gives a false report
  inside AtariAudio's 68000 emulator (pointer-to-member jump table; the
  opcode index is valid when it fires). AddressSanitizer alone is clean.
  Use `-fsanitize=address` only for the Atari tests.
- Songlength is per tune MD5; tunes not in the database play forever in
  the CLI unless `-t` is given.

## Next steps

1. Stephen confirmed the Windows app and the library/search work (2026-11-04:
   "works well enough for now. I like it"). Next: merge PR #2, then Android.
   Still worth testing real HVSC tunes: an RSID digi tune and a 2SID tune.
2. Android (PR #3): Stephen installs ChipDeck.apk and checks playback
   (SID and SNDH/YM), the library on phone storage/SD card, background
   playback with the screen off, and notification controls. Then: audio
   focus (pause for calls/other apps), a real app icon (both platforms),
   signing secrets for in-place updates, battery check (maybe a lighter
   resampler on phones).
3. SNDH/YM: Stephen tries chipdeck-cli with real tunes from the SNDH
   archive (include an STE DAC tune and a digidrum YM). Then add .sndh/.ym
   (and .snd) to the app's file filters; `cd_probe_file` already handles
   them. Later: seeking (`FastForward`), per-voice mute/VU via
   `AudioRenderWithVisualInfos`, browsing the SNDH archive zip
   (SNDH_YM_PLAN.md milestones A3 to A5).
4. Nice to have: drag and drop files onto the window, STIL comments,
   HVSC browser, app icon, installer (MSIX or Inno Setup).
