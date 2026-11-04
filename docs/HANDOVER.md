# ChipDeck handover

Read this first. It is the single source of truth for picking up the work.
Detailed history and research live in [NOTES.md](NOTES.md).

## Goal

ChipDeck is a retro chiptune player for **Windows and Android**. First
target: play C64 **.sid** files on Windows. Also Atari ST **.sndh** and
**.ym** (done in the core and CLI). Later: Android, possibly more chip formats.

## Current state (2026-11-04)

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
  The shared library and so the Flutter app pick it up automatically; the
  app's file filters still need .sndh/.ym. Not yet tried with real SNDH
  archive tunes (only our own generated test tunes). Plan and engine
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
app/                      Flutter GUI (lib/native FFI, lib/player state, lib/ui widgets)
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

App features: playlist (files or whole folders, searchable, remembered
between runs), now playing (title, author, released, PSID/RSID, 6581/8580,
PAL/NTSC, 2SID/3SID), oscilloscope, per-voice activity (waveform, note,
level), progress with Songlengths support, transport, subtune picker,
volume, auto-advance modes (all subtunes then next, next tune, repeat),
shuffle, settings (SID model, Songlengths.md5, default length).
Keys: Space play/pause, Left/Right subtune, N/P tune, +/- volume.

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

- No KERNAL/BASIC ROMs bundled. Most tunes play fine; a few RSID tunes need
  them (`--kernal/--basic/--chargen`). Commodore ROMs are copyrighted, so
  we should ship open replacement ROMs or let users point to their own.
- Only .sid (PSID/RSID) tested. libsidplayfp also loads .prg/.p00/.mus.
- SNDH/YM: tested only with our own generated tunes in the cloud. No
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

1. Stephen tries the Windows app build and gives feedback on the UI.
   Still worth testing real HVSC tunes: an RSID digi tune and a 2SID tune.
2. Android: add `externalNativeBuild` to `app/android/app/build.gradle.kts`
   pointing at the repo root CMakeLists (`CHIPDECK_BUILD_CLI=OFF`,
   `CHIPDECK_BUILD_TESTS=OFF`), check miniaudio on AAudio, file access
   via the Storage Access Framework, and maybe INTERPOLATE sampling to
   save battery.
3. SNDH/YM: Stephen tries chipdeck-cli with real tunes from the SNDH
   archive (include an STE DAC tune and a digidrum YM). Then add .sndh/.ym
   (and .snd) to the app's file filters; `cd_probe_file` already handles
   them. Later: seeking (`FastForward`), per-voice mute/VU via
   `AudioRenderWithVisualInfos`, browsing the SNDH archive zip
   (SNDH_YM_PLAN.md milestones A3 to A5).
4. Nice to have: drag and drop files onto the window, STIL comments,
   HVSC browser, app icon, installer (MSIX or Inno Setup).
