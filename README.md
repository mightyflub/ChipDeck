# ChipDeck

Retro chiptune player for Windows and Android. Plays C64 `.sid` (via
libsidplayfp/reSIDfp), Atari ST `.sndh` and `.ym` (AtariAudio), Amiga `.mod`
and Fasttracker 2 `.xm` (libxmp), Chris Huelsbeck's TFMX (`mdat.*` + `smpl.*`;
Amiga via libtfmxaudiodecoder, Atari ST TFMX-ST via ChipDeck's own replay port)
and Jochen Hippel TFMX / Future Composer, with a Flutter app and a command-line
player.

## Download

Ready-made builds are on the
[Releases page](https://github.com/mightyflub/ChipDeck/releases):
`ChipDeck-<version>-windows-x64.zip` (unzip and run `chipdeck.exe`) and
`ChipDeck-<version>-android.apk` (copy to the device and open it; allow
"install unknown apps"). Test builds of work in progress are artifacts of
the [build workflow](https://github.com/mightyflub/ChipDeck/actions/workflows/build.yml).

## Which platforms are tested

| Platform | What | Status |
| --- | --- | --- |
| Windows 10/11 x64 | App | **Tested** (the owner's PC, every release) |
| Windows 10/11 x64 | `chipdeck-cli` | **Tested** (the owner's PC) |
| Android (arm64) | App (APK) | **Tested** on an Ayn Thor (landscape, dual screen) |
| Linux x64 | App | Built and unit-tested in CI and used for development screenshots; not tested as a player by a user |
| Linux x64 | `chipdeck-cli` | Built, tested (`ctest`) and rendering test tunes to WAV in CI; not tested by a user |
| Windows x64 via MinGW (cross-compiled on Linux) | `chipdeck-cli` | Used for early test builds; not built in CI |
| Android 32-bit ARM / x86_64 | App (same APK) | **Untested** (the APK includes them) |
| macOS | `chipdeck-cli` | **Untested** (no Mac available); should build with CMake, see below |
| macOS, iOS | App | **Not supported yet**: the app has no macOS or iOS runner |

Every build has a version number, shown in the app's Settings title.

## Build instructions

Clone first:

```
git clone https://github.com/mightyflub/ChipDeck
cd ChipDeck
```

The native core (`core/`, C++17) and the command-line player (`cli/`) build
with CMake 3.20+. The app (`app/`) is Flutter 3.47.9 (stable); its Windows,
Linux and Android builds compile the native core automatically.

### Windows: command-line player (tested)

Visual Studio 2022 or newer with "Desktop development with C++" (includes
CMake). From a "Developer PowerShell for VS":

```
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release
build\Release\chipdeck-cli.exe path\to\tune.sid
```

### Windows: app (tested)

Visual Studio as above, plus Flutter 3.47.9 and Windows Developer Mode
(Settings > System > For developers; Flutter needs it for plugin links).

```
cd app
flutter pub get
flutter build windows --release --dart-define=CHIPDECK_VERSION=0.11.0-local
```

The app is in `app\build\windows\x64\runner\Release\` (`chipdeck.exe` plus
the DLLs and `data` folder next to it; copy the whole folder).

### Android: app (tested on the Ayn Thor)

Flutter 3.47.9, JDK 17 and the Android SDK with the NDK and CMake (Android
Studio's SDK Manager installs them).

```
cd app
flutter pub get
flutter build apk --release --dart-define=CHIPDECK_VERSION=0.11.0-local
```

The APK is `app/build/app/outputs/flutter-apk/app-release.apk`. Without
`app/android/key.properties` it is signed with a debug key, so it will not
install over the official APKs (uninstall those first). See
[docs/HANDOVER.md](docs/HANDOVER.md) for release signing.

### Linux: command-line player (CI only)

GCC or Clang, CMake and the ALSA/PulseAudio headers miniaudio uses at run
time (nothing extra is needed to build).

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build
./build/chipdeck-cli tune.sid
```

### Linux: app (CI only)

```
sudo apt install ninja-build libgtk-3-dev clang cmake
cd app
flutter pub get
flutter build linux --release --dart-define=CHIPDECK_VERSION=0.11.0-local
build/linux/x64/release/bundle/chipdeck
```

### Windows command-line player cross-compiled on Linux (untested lately)

```
sudo apt install g++-mingw-w64-x86-64-posix
cmake -S . -B build-win -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
cmake --build build-win -j
```

### macOS: command-line player (untested)

Xcode command-line tools and CMake (`brew install cmake`). Nobody has tried
this yet; miniaudio and the bundled libraries support macOS, so it should
work, but expect to fix small things.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/chipdeck-cli tune.sid
```

### macOS and iOS app (not supported yet)

The Flutter app has no `macos/` or `ios/` folder. Adding one would mean
`flutter create --platforms=macos .` (or `ios`) in `app/` and building the
native core as `libchipdeck.dylib` (macOS) or a framework (iOS) for
`app/lib/native/chipdeck_ffi.dart` to load. Not planned unless asked.

## Using chipdeck-cli

```
chipdeck-cli tune.sid                 play the default subtune
chipdeck-cli -s 3 tune.sid            start at subtune 3
chipdeck-cli -t 30 -w out.wav x.sid   render 30 s to WAV
chipdeck-cli -i tune.sid              show info only
```

`chipdeck-cli` without arguments lists every option.

## More

See [docs/HANDOVER.md](docs/HANDOVER.md) for the current state,
architecture, release process and next steps.

License: GPL-2.0-or-later (see LICENSE). Third-party code: see
[third_party/README.md](third_party/README.md).
