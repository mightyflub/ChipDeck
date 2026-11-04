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
