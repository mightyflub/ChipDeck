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

## 2026-11-04: Proposed stack (awaiting Stephen's go-ahead)

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
