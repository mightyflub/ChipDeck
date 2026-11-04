# ChipDeck

Retro chiptune player for Windows and Android. Plays C64 `.sid` files today
(via libsidplayfp/reSIDfp); Atari ST `.sndh` and a full GUI are planned.

Quick start on Windows (Visual Studio 2022):

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
build\Release\chipdeck-cli.exe tune.sid
```

See [docs/HANDOVER.md](docs/HANDOVER.md) for the current state, architecture,
build instructions and next steps.

License: GPL-2.0-or-later (see LICENSE). Third-party code: see
[third_party/README.md](third_party/README.md).
