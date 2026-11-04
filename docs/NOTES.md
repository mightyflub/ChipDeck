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
