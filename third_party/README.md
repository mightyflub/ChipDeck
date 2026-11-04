# Third-party code

| Library | Version | License | Source |
| --- | --- | --- | --- |
| libsidplayfp | 3.1.2 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libsidplayfp/releases/tag/v3.1.2 |
| libresidfp (reSIDfp) | 1.2.3 | GPL-2.0-or-later | release tarball from https://github.com/libsidplayfp/libresidfp/releases/tag/v1.2.3 |
| miniaudio | 0.11.26 | Public domain / MIT-0 | https://github.com/mackron/miniaudio/tree/0.11.26 |

Why vendored release tarballs instead of git submodules: the tarballs ship the
pre-assembled 6502 driver binaries (`psiddrv.bin`, `sidplayer1/2.bin`), so no
`xa65` cross-assembler or autotools is needed. `CMakeLists.txt` in this folder
replaces the upstream autotools build and generates the few `*.h.in` headers.

Only `src/` plus license/readme files were copied. Removed from libsidplayfp:
the exSID and USBSID hardware builders (we only emulate) and the Makefiles.

Upgrading: download the new tarballs, replace `src/`, update the version
numbers in `CMakeLists.txt` (here) and in `core/src/chipdeck.cpp`
(`cd_version`), compare the source lists against upstream `Makefile.am`,
then run the tests.
