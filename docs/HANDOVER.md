# ChipDeck handover

Read this first. It is the single source of truth for picking up the work.
Detailed history and research live in [NOTES.md](NOTES.md).

## Goal

ChipDeck is a retro chiptune player for **Windows and Android**. First
target: play C64 **.sid** files on Windows. Later: a GUI, Android, then
Atari ST **.sndh**, possibly more chip formats.

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
- A parallel thread is adding SNDH/YM playback to the core (branch
  claude/project-thread-lu47hk). It owns `core/src/chipdeck.cpp` changes;
  coordinate before editing that file.
- Unit tests pass on Linux (also under AddressSanitizer). HVSC download
  hosts are blocked from the cloud dev container, so real-tune testing
  happens on Stephen's PC.

## Repository layout

```
CMakeLists.txt            top-level build (core, cli, tests)
core/include/chipdeck/    public C API (chipdeck.h)
core/src/                 implementation (libsidplayfp wrapper, chipdeck_audio.cpp output)
app/                      Flutter GUI (lib/native FFI, lib/player state, lib/ui widgets)
cli/main.cpp              chipdeck-cli (miniaudio output, WAV export, keys)
tests/core_test.cpp       core tests, run with ctest
tests/data/               chipdeck-test.sid (our own public-domain tune)
tools/make_test_sid.py    regenerates the test tune
third_party/              vendored libsidplayfp, libresidfp, miniaudio + CMake build
cmake/                    toolchain file for MinGW cross-compile
.github/workflows/        CI: Windows (MSVC) + Linux
docs/                     HANDOVER.md (this), NOTES.md (log)
```

## Architecture

```
+-------------------+      +--------------------------------+
| UI                |      | chipdeck-core (C++17, C API)   |
| now: chipdeck-cli | ---> |  - libsidplayfp + reSIDfp (SID)|
| next: Flutter     | FFI  |  - psgplay (SNDH, later)       |
|   (Win+Android)   |      |                                |
+-------------------+      +--------------------------------+
         |
         v
    miniaudio (WASAPI on Windows, AAudio/OpenSL on Android)
```

- The core only produces PCM (int16 stereo, 48 kHz in the CLI); the app
  owns the audio device. Every core call is mutex-locked so `cd_render()`
  can run on the audio thread while the UI changes subtunes.
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
keys: n/p next/prev subtune, space pause, q quit
```

Songlengths.md5 is in HVSC at `C64Music/DOCUMENTS/Songlengths.md5`.

## Known limitations

- No KERNAL/BASIC ROMs bundled. Most tunes play fine; a few RSID tunes need
  them (`--kernal/--basic/--chargen`). Commodore ROMs are copyrighted, so
  we should ship open replacement ROMs or let users point to their own.
- Only .sid (PSID/RSID) tested. libsidplayfp also loads .prg/.p00/.mus.
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
3. Merge SNDH/YM support from the other thread; make sure the app's
   file filters and probe handle .sndh/.ym.
4. Nice to have: drag and drop files onto the window, STIL comments,
   HVSC browser, app icon, installer (MSIX or Inno Setup).
