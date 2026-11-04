# ChipDeck

Retro chiptune player for Windows and Android. Plays C64 `.sid` (via
libsidplayfp/reSIDfp), Atari ST `.sndh` and `.ym` (AtariAudio), Amiga `.mod`
and Fasttracker 2 `.xm` (libxmp), with a Flutter app and a command-line player.

Quick start on Windows (Visual Studio 2022):

```
cmake -S . -B build -A x64
cmake --build build --config Release
build\Release\chipdeck-cli.exe tune.sid
```

See [docs/HANDOVER.md](docs/HANDOVER.md) for the current state, architecture,
build instructions and next steps.

License: GPL-2.0-or-later (see LICENSE). Third-party code: see
[third_party/README.md](third_party/README.md).
