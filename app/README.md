# ChipDeck app (Flutter)

The ChipDeck GUI for Windows (first), Linux and later Android. It loads the
native core (`chipdeck.dll` / `libchipdeck.so`, built from the repo root
CMakeLists) through `dart:ffi`. The Windows and Linux runners build that
library automatically as part of `flutter build`.

```
cd app
flutter pub get
flutter run -d windows        # or: flutter build windows --release
```

Output: `app/build/windows/x64/runner/Release/` (run `chipdeck.exe`; keep the
DLLs and `data/` folder next to it).

Code map:

- `lib/native/chipdeck_ffi.dart`: FFI bindings to `core/include/chipdeck/chipdeck.h`
- `lib/player/player_controller.dart`: playlist, transport, settings, auto-advance
- `lib/ui/`: theme, home layout, playlist, now playing, visualiser, settings

See `../docs/HANDOVER.md` for the bigger picture.
