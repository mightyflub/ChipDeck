# ChipDeck handover

Read this first. It is the single source of truth for picking up the work.
Detailed history and research live in [NOTES.md](NOTES.md).

## Goal

ChipDeck is a retro chiptune player for **Windows and Android**. First
target: play C64 **.sid** files on Windows. Later: Android, then Atari ST
**.sndh**, possibly more chip formats.

## Current state (2026-11-04)

- No code yet. The repo contains only README and these docs.
- Research done: SID engine options and a proposed stack (see below).
- The repo Stephen linked (sakirhossn/SidPlayer) turned out to be an
  Electron video player with no SID code; not used.
- **Waiting on Stephen** to approve the stack before building.

## Architecture (proposed)

```
+-------------------+      +--------------------------------+
| UI                |      | chipdeck-core (C++17, C API)   |
| step 1: CLI       | ---> |  - libsidplayfp + reSIDfp (SID)|
| step 2: Flutter   | FFI  |  - psgplay (SNDH, later)       |
|   (Win+Android)   |      |  - miniaudio output            |
+-------------------+      +--------------------------------+
```

## Key decisions

| Decision | Choice | Why |
| --- | --- | --- |
| SID emulation | libsidplayfp with reSIDfp | Most accurate open engine, maintained, portable C++ |
| Audio output | miniaudio | One header, WASAPI on Windows, AAudio on Android |
| Build system | CMake | Works with MSVC and the Android NDK |
| License | GPL-2.0-or-later (pending) | Required by libsidplayfp |
| UI | CLI first, then Flutter (pending) | Fast proof on Windows, one UI for both platforms |

## How to build / run

Not applicable yet. Will be filled in with the first code.

## Next steps

1. Stephen approves the stack (or picks Qt instead of Flutter).
2. Add libsidplayfp and miniaudio as git submodules under `third_party/`.
3. Write a CMake build for libsidplayfp (upstream uses autotools).
4. Build `chipdeck-core` with the C API and a `chipdeck-cli` player.
5. Test on Windows (E:\Claude) with HVSC tunes, including an RSID digi tune
   and a 2SID tune.
6. Add Songlengths.md5 support so tracks end on time.
7. Then: Flutter UI, Android build, SNDH via psgplay.
