# Third-party code

| Library | Version | License | Source |
| --- | --- | --- | --- |
| libsidplayfp | 3.1.2 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libsidplayfp/releases/tag/v3.1.2 |
| libresidfp (reSIDfp) | 1.2.3 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libresidfp/releases/tag/v1.2.3 |
| AtariAudio | 1.27 | MIT (includes Musashi 68000 core, MIT-style; ICE depacker, public domain; LZH depacker; timedb song lengths from the sc68 project) | `git archive 1.27 src LICENSE README.md` of https://github.com/arnaud-carre/AtariAudio |
| libxmp | 4.6.3 | MIT | `src/` (minus `bitrot/` and `lite/`), `include/`, `cmake/libxmp-sources.cmake`, README, docs/COPYING of tag libxmp-4.6.3 at https://github.com/libxmp/libxmp |
| libtfmxaudiodecoder | 1.0.14 (master 93b99ec, 2026-11-02) | GPL-2.0-or-later | `src/` (minus `Makefile.am`, `Config.h.in`), COPYING, README.md, NEWS.md, TFMX.md of https://github.com/mschwendt/libtfmxaudiodecoder; `src/Config.h` is ours |
| miniaudio | 0.11.26 | Public domain / MIT-0 | https://github.com/mackron/miniaudio/tree/0.11.26 |

Why vendored release tarballs instead of git submodules: the tarballs ship the
pre-assembled 6502 driver binaries (`psiddrv.bin`, `sidplayer1/2.bin`), so no
`xa65` cross-assembler or autotools is needed. `CMakeLists.txt` in this folder
replaces the upstream autotools build and generates the few `*.h.in` headers.

Only `src/` plus license/readme files were copied. Removed from libsidplayfp:
the exSID and USBSID hardware builders (we only emulate) and the Makefiles.

## Local patches (ChipDeck)

Per-channel oscilloscopes need data the libraries do not expose. All
changes are marked "ChipDeck patch" in the source; re-apply them after an
upgrade (`grep -rn "ChipDeck patch" third_party`):

- libresidfp `Filter.h`: keep the last output of each voice
  (`lastVoiceOut`), and accessors for the volume nibble and voice 3 off.
- libresidfp `SID.h`, `residfp/residfp.h/.cpp`: optional voice tap
  (`setVoiceTap`); `clock(cycles, buf)` writes voice 1-3 and the volume
  nibble (as a waveform) for every output sample.
- libsidplayfp `sidemu.h`, `builders/residfp-builder/residfp-emu.cpp`:
  a per-voice buffer next to the sample buffer, passed as the tap.
- libsidplayfp `player.h/.cpp`, `sidplayfp/sidplayfp.h/.cpp`:
  `voiceBuffers()` returns those buffers, like `buffers()`.

- libxmp `src/common.h`, `src/mixer.c`, `include/xmp.h`: a per-channel
  output tap (`xmp_chipdeck_set_tap`, `xmp_chipdeck_read_tap`). The
  softmixer copies the mix buffer before each voice and credits the
  difference to the voice's tracker channel.

- libtfmxaudiodecoder `src/LamePaulaMixer.h/.cpp`, `tfmxaudiodecoder.h/.cpp`:
  a per-voice output tap for the scopes (`tfmxdec_chipdeck_set_tap`),
  including the four virtual voices of TFMX 7V.
- libtfmxaudiodecoder `src/ChipDeckFile.h` (new), `DecoderProxy.cpp`,
  `Chris/SamplesFile.cpp`, `Chris/DNS/DNSDecoder.cpp`: open files by UTF-8
  path (wide-char API on Windows), so names with accents work.
- libtfmxaudiodecoder `DecoderProxy.cpp`: fix a decoder object leaked by
  every format probe (`maybeOurs`).

TFMX-ST (Atari ST TFMX) is not in any library: `core/src/tfmxst_backend.cpp`
is ChipDeck's own C++ port of Chris Huelsbeck's ST replay routine, made from
the commented 68000 source in Wanted Team's TFMX ST EaglePlayer as shipped
with UADE (https://gitlab.com/uade-music-player/uade,
`amigasrc/players/wanted_team/TFMX_ST/TFMX ST_v1.asm`). It drives
AtariAudio's YM2149 emulation (`Ym2149c`).

AtariAudio is unchanged (its `AudioRenderWithVisualInfos` is enough).

libxmp is built by our own CMake block from upstream's source lists
(`libxmp/cmake/libxmp-sources.cmake`, including ProWizard and depackers).

Upgrading: download the new tarballs, replace `src/`, update the version
numbers in `CMakeLists.txt` (here) and in `core/src/chipdeck.cpp`
(`cd_version`), compare the source lists against upstream `Makefile.am`,
re-apply the local patches above, then run the tests.
