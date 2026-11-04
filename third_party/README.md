# Third-party code

| Library | Version | License | Source |
| --- | --- | --- | --- |
| libsidplayfp | 3.1.2 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libsidplayfp/releases/tag/v3.1.2 |
| libresidfp (reSIDfp) | 1.2.3 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libresidfp/releases/tag/v1.2.3 |
| AtariAudio | 1.27 | MIT (includes Musashi 68000 core, MIT-style; ICE depacker, public domain; LZH depacker; timedb song lengths from the sc68 project) | `git archive 1.27 src LICENSE README.md` of https://github.com/arnaud-carre/AtariAudio |
| libxmp | 4.6.3 | MIT | `src/` (minus `bitrot/` and `lite/`), `include/`, `cmake/libxmp-sources.cmake`, README, docs/COPYING of tag libxmp-4.6.3 at https://github.com/libxmp/libxmp |
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

AtariAudio is unchanged (its `AudioRenderWithVisualInfos` is enough).

libxmp is built by our own CMake block from upstream's source lists
(`libxmp/cmake/libxmp-sources.cmake`, including ProWizard and depackers).

Upgrading: download the new tarballs, replace `src/`, update the version
numbers in `CMakeLists.txt` (here) and in `core/src/chipdeck.cpp`
(`cd_version`), compare the source lists against upstream `Makefile.am`,
re-apply the local patches above, then run the tests.
