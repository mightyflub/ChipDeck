# SNDH and YM support plan

Status: **plan only, no code yet** (2026-11-04). Builds on the core design in
[HANDOVER.md](HANDOVER.md). Research log is in [NOTES.md](NOTES.md).

## Recommendation in one paragraph

Use **AtariAudio** (https://github.com/arnaud-carre/AtariAudio, MIT) as the
single engine for both Atari ST formats, **.sndh** and **.ym**. It is the
emulation library inside the sndh-player repo the owner linked, split out into
its own repo by the same author. It is small (about 14 C++ files), has no
dependencies, uses no file I/O and no floating point, builds with plain CMake,
is thread safe per instance, and is already used as a library by other
players (BZR Player 2, rePlayer). It replaces psgplay, which the earlier stack
proposal named for SNDH. Keep psgplay only as a fallback if we hit SNDH files
AtariAudio cannot play.

## What the linked repo is

`arnaud-carre/sndh-player` ("SNDH and YM Archive Player", v1.23, last commit
2026-11-04, MIT) is a desktop **app**, not a library:

- UI: Dear ImGui + GLFW + OpenGL, Windows and macOS only (its CMake file
  refuses other platforms).
- Extras: opens the whole 100 MiB SNDH ZIP archive, multi-threaded archive
  scanning, oscilloscopes, WAV export, seek bar.
- The actual sound emulation is the **AtariAudio** git submodule.

So for ChipDeck we take **AtariAudio**, not the app. The app is still useful
as a reference for: ZIP archive browsing (`SndhArchive.cpp`), streaming on a
worker thread (`AsyncSndhStream.cpp`), and as an A/B listening reference when
testing our output.

## Candidates compared

| Library | Formats | License | Language / build | Portability to MSVC + Android NDK | Maintained | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **AtariAudio 1.27** | SNDH (incl. ICE packed, STE DAC, blitter), YM2/3/3b/5/6, MIX1, YMT1/2 (LZH packed) | MIT (Musashi 68k: MIT-style; ICE depacker: public domain; LZH: free; timedb song lengths from the sc68 project) | C++17, plain sources, CMake example | Very good: no OS headers, no intrinsics, no `#pragma`/MSVC-only code, no float | Yes, last commit 2026-10-29 | **Use** |
| psgplay | SNDH only (no .ym) | GPL-2.0 | C (GNU dialect), GNU make, generated m68k ops, prebuilt TOS image | Fair: fine with GCC/Clang (so NDK and MinGW OK), needs a CMake port and fixes for MSVC | Yes, last commit 2026-09-08 | Fallback for SNDH only |
| StSound | YM only | MIT | C++ | Good | **Deprecated by its author** in favour of AtariAudio | Skip |
| ayumi | AY-3-8910 / YM2149 chip only, no file parsers, no 68000 | MIT | C, 2 files | Excellent | Quiet since 2021 | Not for SNDH/YM; keep in mind for future ZX Spectrum formats (.ay, .pt3, .vtx) |
| sc68 | SNDH, SC68 | GPL | C, autotools | Poor, old | Mostly dormant | Skip |

Why not psgplay as primary: it only covers SNDH, so YM would need a second
library anyway; it is built with GNU make and GCC extensions, so we would have
to write and maintain a CMake/MSVC port; and its API takes uncompressed data
only, so we would also need our own ICE depacker. AtariAudio does all of this
in one small library.

License fit: ChipDeck will be GPL-2.0-or-later because of libsidplayfp. MIT
code can be included in a GPL program, so AtariAudio fits with no change. We
must keep its LICENSE file and credits (Musashi, ICE depacker, timedb) in our
third-party notices.

## AtariAudio API in brief

```cpp
AtariAudioRenderer* r = AtariAudioRenderer::Create(data, size, sampleRate);
const auto& info = r->GetSongInfo();   // subsongCount, defaultSubsong, name,
                                       // author, year, fileFormat, ...
r->InitSubSong(n);                     // 1-based, required before rendering
uint32_t len = r->GetSubsongDurationSample(n);   // 0 = unknown
r->AudioRender(int16_buf, count);      // mono, signed 16-bit, loops forever
r->FastForward(count);                 // emulate without output (for seek)
r->AudioRenderWithVisualInfos(...);    // + per-voice VU levels
r->MuteVoices(mask);                   // YM A/B/C and STE DAC
AtariAudioRenderer::Destroy(r);
```

It takes the file as a memory buffer and copies what it needs, so the caller
can free the buffer after `Create`.

## How it fits the chipdeck-core design

The core was proposed as a C++ library with a small C API wrapping
libsidplayfp. To add Atari formats cleanly, the core should have an internal
**backend interface** from day one, so SID is not hard-wired:

```
               chipdeck-core (C API: cd_open, cd_render, ...)
                               |
                     FormatRegistry (probe by magic bytes)
                 /             |                 \
        SidBackend     AtariBackend              (future: AY, VGM, ...)
      (libsidplayfp)   (AtariAudio: .sndh, .ym)
```

Internal C++ interface (sketch):

```cpp
struct TrackInfo { std::string title, author, year, format;
                   int subtunes; int defaultSubtune; };

class Backend {
public:
  virtual ~Backend() = default;
  virtual bool open(const uint8_t* data, size_t size, uint32_t sampleRate) = 0;
  virtual TrackInfo info() const = 0;
  virtual bool selectSubtune(int n) = 0;          // 1-based
  virtual int64_t durationMs(int n) const = 0;    // -1 = unknown
  virtual size_t render(int16_t* stereo, size_t frames) = 0;  // interleaved L/R
  virtual bool seekMs(int64_t ms) = 0;
  virtual uint32_t voiceCount() const = 0;
  virtual void muteVoices(uint32_t mask) = 0;
};
```

### Format detection (probe)

AtariAudio accepts packed files and detects the type itself, but the core
needs to choose a backend first. Probe order on the first bytes:

| Format | Magic |
| --- | --- |
| SID | `PSID` or `RSID` at offset 0 |
| SNDH, ICE packed | `ICE!` at offset 0 (packed SNDH; AtariAudio unpacks) |
| SNDH, raw | `SNDH` at offset 12 |
| YM, LZH packed | `-lh5-` at offset 2 (most .ym files are LZH archives) |
| YM, raw | `YM2!`, `YM3!`, `YM3b`, `YM4!`, `YM5!`, `YM6!`, `MIX1`, `YMT1`, `YMT2` at offset 0 |

File extension is only a tie-breaker, never the main test (many SNDH files
in the wild are named `.snd`).

### Glue details for the AtariBackend

- **Mono to stereo**: AtariAudio outputs mono. The backend duplicates each
  sample to L and R. (The real ST is mono for the YM; STE DAC stereo is
  folded to mono by AtariAudio. Acceptable for v1.)
- **Sample rate**: pass the device rate from miniaudio (usually 48000) to
  `Create`, so no resampling is needed.
- **Subtunes**: AtariAudio is 1-based, same as our C API. `cd_set_subtune(0)`
  means "default subtune" and maps to `SongInfo.defaultSubsong`.
- **Song length**: use `GetSubsongDurationSample`. If 0 (unknown), use the
  player's "default length" setting (same setting as SID tunes not in
  Songlengths.md5, suggested 3:00). The core reports "unknown" and the
  player decides; the core never stops a tune by itself.
- **Seeking**: forward seek = `FastForward(samples)`. Backward seek =
  `InitSubSong(n)` then `FastForward` to the target. Fast forward runs the
  68000, so a 5 minute seek may take a noticeable fraction of a second on a
  phone; do it off the audio thread or show a short wait.
- **Threading**: one renderer per playing track, used only by the audio
  thread (or the ring buffer filler). Metadata scans for the library view
  create their own short-lived instances. Note: `ym2149c.cpp` has one shared
  random seed (`sRndSeed`) used for "noise"; concurrent instances race on it
  harmlessly (only affects noise randomness). We can patch it to per-instance
  if we ever need bit-exact output across threads.
- **Voices and VU meters**: expose 4 voices (YM A, B, C, STE DAC) through
  `muteVoices` and use `AudioRenderWithVisualInfos` for per-voice levels in
  the UI. SID backend exposes its own 3 (or 6/9) voices the same way.

### C API additions

Planned on top of the functions already listed in HANDOVER:

```c
cd_player* cd_open_memory(const void* data, size_t size, uint32_t rate);
const char* cd_format(cd_player*);        /* "PSID", "SNDH", "YM 5", ... */
int64_t     cd_duration_ms(cd_player*, int subtune);  /* -1 = unknown */
int         cd_seek_ms(cd_player*, int64_t ms);
int         cd_voice_count(cd_player*);
void        cd_mute_voices(cd_player*, uint32_t mask);
```

`cd_open_memory` matters for Android, where files come from content URIs and
from inside ZIP archives rather than file paths.

## Build integration

- Add `third_party/AtariAudio` as a git submodule pinned to tag **1.27**.
- Add a CMake static library target `atariaudio` listing its 14 `.cpp` files
  (same list as its `example/AtariAudio2Wav/CMakeLists.txt`), C++17.
  Compile with warnings relaxed for that target only.
- `chipdeck-core` links `atariaudio` privately. Nothing else changes for the
  Flutter side: the C API is format-agnostic.
- Android: same CMake target via the NDK (arm64-v8a, armeabi-v7a, x86_64).
  No source changes expected, since the library has no OS dependencies.

## Milestones

1. **A1, with the SID work:** put the `Backend` interface and probe in the
   core from the start (cost: small; avoids a refactor later).
2. **A2:** add AtariAudio submodule and `AtariBackend`.
   `chipdeck-cli tune.sndh [subtune]` and `chipdeck-cli tune.ym` play on
   Windows. Add `--wav out.wav` to the CLI for A/B checks.
3. **A3:** subtunes, durations, default length, metadata, seeking.
4. **A4:** Android NDK build of the core with both backends.
5. **A5 (UI phase):** voice mute, VU meters, and ZIP archive browsing for
   the official SNDH archive zip (needs a zip reader such as miniz; ICE and
   LZH depacking already live in AtariAudio).

## Test plan

- Sample files ship with AtariAudio in `example/AtariAudio2Wav/musics`
  (SNDH incl. ICE packed and STE DAC, YM incl. LZH packed): use them as the
  first smoke test set. Do not commit them to ChipDeck; fetch in a test script
  or point the test at the submodule path.
- Full set: SNDH archive zip from https://sndh.atari.org/download.php and YM
  files from the same site. Run a headless "render 10 seconds of every
  subtune" sweep to catch crashes and silent output.
- Listen A/B against sndh-player (prebuilt Windows binary on its GitHub
  releases page) for a handful of tunes, including an STE DAC tune and a
  digidrum tune.

## Risks and open questions

- **Compatibility gaps**: some SNDH drivers may need hardware AtariAudio does
  not emulate. Mitigation: psgplay as an optional second SNDH backend later,
  picked per file if AtariAudio fails to init or renders silence.
- **Mono only**: fine for YM; a few STE tunes are stereo. Revisit only if it
  bothers the owner.
- **Not compile-tested yet**: this plan was written from reading the source.
  The first coding step (A2) should build AtariAudio with MSVC and the NDK
  before anything else.
- **Other chip formats later**: ayumi is the natural base for ZX Spectrum /
  Amstrad AY formats if those are wanted.
