# ChipDeck handover

Read this first. It is the single source of truth for picking up the work.
Detailed history and research live in [NOTES.md](NOTES.md).

## Goal

ChipDeck is a retro chiptune player for **Windows and Android**. First
target: play C64 **.sid** files on Windows. Later: a GUI, Android, then
Atari ST **.sndh**, possibly more chip formats.

## Current state (2026-11-04)

- **Milestone 1 done (pending Stephen's test on real hardware):** a
  command-line player `chipdeck-cli` that plays .sid files through the
  speakers or renders them to WAV.
- `chipdeck-core` library with a plain C API (`core/include/chipdeck/chipdeck.h`)
  wraps libsidplayfp 3.1.2 + reSIDfp 1.2.3. This is the piece the future
  Flutter UI and Android app will call.
- Unit tests pass on Linux (also under AddressSanitizer). Windows builds
  with MinGW cross-compile; GitHub Actions builds with MSVC and uploads
  `chipdeck-cli.exe` as an artifact.
- Not yet verified with real HVSC tunes in the cloud (HVSC download hosts
  are blocked from the dev container), only with our own test tune.
- Stack approved by Stephen on 2026-11-04: CLI first, Flutter UI later.

## Repository layout

```
CMakeLists.txt            top-level build (core, cli, tests)
core/include/chipdeck/    public C API (chipdeck.h)
core/src/                 implementation (libsidplayfp wrapper)
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
| UI | CLI now, Flutter later | Approved by Stephen 2026-11-04 |
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

1. Stephen tests `chipdeck-cli.exe` on Windows with real HVSC tunes
   (include an RSID digi tune and a 2SID tune). Fix whatever breaks.
2. Optional: try a smaller CPU budget (INTERPOLATE sampling) for Android.
3. Start the Flutter app (`app/`): Windows desktop first, calling
   `chipdeck-core` as a DLL via dart:ffi (`CHIPDECK_SHARED`), with file
   picker, subtune selector, play/pause, song length, playlist.
4. Android: build `chipdeck-core` with the NDK (CMake already compatible),
   load it from Flutter; audio via miniaudio (AAudio) in the core or a
   Flutter audio plugin.
5. SNDH: evaluate psgplay (GPL-2.0) and add it behind the same C API.
