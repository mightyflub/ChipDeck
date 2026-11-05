# ChipDeck roadmap (from 0.11.0)

Written 2026-11-05. The owner asked for all nine ideas below, split into
small releases that are each easy to test. Nothing here is built yet.

Each release is one version bump and one PR. The owner asked
(2026-11-05) for the first three features in one build (0.12.0) and the
next three in another (0.13.0); the rest are one release each. It is tested on Windows first
(the main test platform), then on the Android test handheld. As always,
every feature lands on both platforms in the same release, or is listed in
HANDOVER.md under "Pending on one platform". Every release also updates
HANDOVER.md, NOTES.md and `docs/releases/<version>.md`.

The order follows dependencies first and then value. Small releases come
early so there is always something quick to try. The order can change at
any time: the releases do not depend on each other except where a
"Needs" line says so.

## What already exists (checked in the code)

Some of the ideas are partly done, so their releases are smaller:

- **Song lengths for SID:** HVSC `Songlengths.md5` is already used (picked
  up automatically or set in Settings), and a tune moves on at its length.
  SNDH (TIME tag), YM, MOD/XM and TFMX tunes already report lengths too.
  What is missing is **seeking** and a scrub bar.
- **SID model:** Settings already has Auto / 6581 / 8580.
- **C64 ROMs:** the core already has `cd_set_roms()`. Only the app setting
  is missing.
- **Future Composer:** already plays through libtfmxaudiodecoder (0.8.0).
  It only needs checking with real files.
- **S3M, IT, MED and more:** libxmp (already bundled) plays them. The app
  just doesn't offer them yet.
- **Android background and lock screen:** already done (foreground
  service, MediaSession, notification controls, pause on headphone
  unplug). Missing: audio focus (pause for calls) and seeking from the
  lock screen. **Windows media keys** are not done.
- **Muting voices:** every bundled engine can already mute single voices
  (libsidplayfp `mute()`, AtariAudio `MuteVoices()`, libxmp
  `xmp_channel_mute()`, libtfmxaudiodecoder `tfmxdec_mute_voice()`; our own
  TFMX-ST player can do it directly).

## The releases at a glance

| Version | What | Size | Mostly |
| --- | --- | --- | --- |
| 0.12.0 | Mute and solo voices, seeking and a scrub bar, C64 ROM setting | M | core + Now playing + Settings |
| 0.13.0 | Play history and "Most played", Windows media keys and Android audio focus, more module formats (S3M, IT, MED...) | M | Dart, platform code, format list |
| 0.14.0 | HVSC download and update in the app | L | new downloads code |
| 0.15.0 | SNDH archive download and update | M | reuses 0.14.0 |
| 0.16.0 | Modland browsing and downloads | L | reuses 0.14.0 |
| 0.17.0 | Sound options: SID filter, Amiga stereo separation, gap between tunes | M | core + Settings |
| 0.18.0 | Crossfade between tunes | M | audio engine |
| 0.19.0 | Export to WAV and FLAC | M | core + new dialog |
| 0.20.0 | AHX and HivelyTracker | M | new engine |
| 0.21.0 | SAP (Atari 8-bit) | M | new engine |

S = a day or less of work, M = a few days, L = about a week.

## New libraries and licences

ChipDeck is GPL-2.0-or-later, so anything added must be GPL-2-compatible.

| Release | Library | Licence | Notes |
| --- | --- | --- | --- |
| 0.13.0 | Windows SystemMediaTransportControls (C++/WinRT, part of the Windows SDK) | Windows SDK | Written in the Windows runner; no extra package. A pub package such as `smtc_windows` would pull in a Rust toolchain, so avoid it. |
| 0.14.0-0.16.0 | `archive` (Dart) | MIT | Unzips downloads. |
| 0.14.0 | LZMA SDK (only if HVSC needs 7z) | Public domain | Only if no zip of HVSC is available; to be checked. |
| 0.14.0-0.16.0 | `dart:io` HttpClient | (Dart SDK) | No extra package needed for downloads. |
| 0.19.0 | libFLAC | BSD-3-Clause | FLAC encoding. WAV needs nothing (the CLI already writes WAV). |
| 0.20.0 | HivelyTracker replayer (hvl_replay) | BSD-3-Clause | Plays .hvl and .ahx. |
| 0.21.0 | ASAP | GPL-2.0-or-later | Plays .sap (and .cmc, .rmt, .tmc and others). |

Each one goes into `third_party/` with its licence and is listed in
`third_party/README.md` and on the app's Licenses page, like the libraries
already there. No ROMs, tunes or archive contents are ever added to git.

---

## 0.12.0 (part 1): Mute and solo voices

**Why first:** the per-channel scopes are already there and every engine
can mute voices, so this is a small, fun change.

**Core:** new `cd_set_channel_mute(p, ch, muted)` and
`cd_channel_muted(p, ch)`, using the same channel numbers as
`cd_channel_name()`. Each backend maps it to its engine's mute call. The
mute state is kept when changing subtune (AtariAudio unmutes on
`InitSubSong`, so the core sets it again) and cleared when a new file loads.
For SID, "Digi" maps to libsidplayfp voice 3 (samples); check that our
`$D418` digi scope matches what gets muted. Tests in each backend test file:
a muted channel's scope is silent and the mix changes.

**App:** click or tap a scope to mute or unmute it; right-click, or long
press on Android, to solo it (again to un-solo). Muted scopes are dimmed and
show a crossed speaker. An "Unmute all" button appears while anything is
muted. Keys 1-9 toggle channels 1-9 and 0 unmutes all. In "Mix" scope view
the toggles appear as small numbered chips instead. The Android
second-screen controls show which voices are muted (read only to start
with).

**Test on Windows:** play a 3-voice SID and mute each voice by clicking its
scope; solo the bass; try a 2SID tune (6 voices); a digi tune (mute Digi);
an SNDH with STE DAC; a 4-channel MOD and a 16+ channel XM; an Amiga TFMX
and a TFMX-ST tune. Change subtune: mutes stay. Load another tune: all
voices are back. Keys 1-9 and 0.
**Test on Android:** tap and long press on scopes on the main screen; the
"Unmute all" button; the second screen shows the state.

## 0.12.0 (part 2): Seeking and a scrub bar

**Core:** new `cd_seek_ms(p, ms)`. libxmp and libtfmxaudiodecoder have
their own seek (`xmp_seek_time`, `tfmxdec_seek`). SID, SNDH, YM and TFMX-ST
have none, so the core renders forward without output (AtariAudio has
`FastForward()`; for SID, render without the resampler, scopes and mixing).
Seeking backwards restarts the subtune and renders forward. A long forward
seek on a SID tune may take a moment, so it runs off the audio thread: the
player goes quiet, seeks, then carries on. Measure how fast this is on the
test handheld; if it is slow there, show a spinner on the scrub bar.

**App:** the position bar in Now playing becomes a scrub bar (drag or
click). Keys: Shift+Left/Right jump 10 s (plain Left/Right already change
subtune). The Android notification and lock screen get a seek bar
(MediaSession `ACTION_SEEK_TO` with the position and length). The
second-screen controls get the scrub bar too. Tunes with no known length
can still seek forward up to the default length setting.

**Test on Windows:** seek forward and back in a SID with a Songlengths
entry, a long SNDH, a YM, a MOD/XM and a TFMX tune; seek near the end (it
should move on to the next tune as usual); seek while paused; seek a 2SID
and a digi tune (digis should still sound right afterwards).
**Test on Android:** the same, plus the seek bar in the notification and on
the lock screen, and on the second screen. Note how long a 3-minute jump
takes on a SID tune.

## 0.12.0 (part 3): C64 ROM setting

**Needs:** nothing.

**App:** Settings gets "C64 ROMs (optional)": pick the KERNAL, BASIC and
CHARGEN files one by one or point at a folder that has them (VICE names
such as `kernal-901227-03.bin`, `basic-901226-01.bin`,
`chargen-901225-01.bin` are recognised). Sizes are checked (8 KB, 8 KB,
4 KB); the setting shows which ROMs are set. Passed to `cd_set_roms()` on
the player and to the library's tune probes. The scan report and the
"won't play" message for a BASIC tune say that a BASIC ROM is needed and
where to set it. Re-probe the RSID tunes that failed when ROMs are added.
ROMs are never shipped or downloaded by the app.

**Test on Windows:** play an RSID BASIC tune without ROMs (clear message),
set the ROMs, play it again; refresh the library and check that tunes that
failed before now show; clear the setting.
**Test on Android:** set the ROMs from phone storage and play the same
tune.

## 0.13.0 (part 1): Play history, play counts and "Most played"

**Needs:** nothing. All Dart, same code on both platforms.

**App:** a tune counts as played after 30 s or when it reaches its end
(whichever comes first). The app keeps play counts and last-played time
per file (and per subtune for SID/SNDH) in a small `history.json` next to
`library.json`, and the last 500 plays in order. The Playlists browser
gets three smart lists at the top: **Recently played**, **Most played**
(top 100) and **Never played** (library tunes with no plays, handy with
random order). Smart lists update themselves and can't be edited, but can
be played, shuffled and copied into "Playing Now" or a playlist. Library
rows and Now playing show the play count. Settings: "Clear play history".

**Test on Windows:** play some tunes for more and less than 30 s; check the
counts, the order of Recently played and Most played; restart the app;
play Most played in random order; clear history.
**Test on Android:** the same, plus that tunes played with the screen off
are counted.

## 0.13.0 (part 2): Windows media keys, Android audio focus and lock-screen polish

**Needs:** the seeking in 0.12.0, for the lock screen and SMTC.

**Windows:** register with SystemMediaTransportControls in the Windows
runner (C++/WinRT, a method channel to Dart in `lib/platform/`). This
gives play/pause/next/previous media keys (also on Bluetooth headsets and
keyboards) and the Windows media overlay with title and composer, working
while ChipDeck is in the background.

**Android:** request audio focus when playback starts: pause for a phone
call or another app, lower the volume for a short sound (navigation
prompt), carry on after a short interruption. Show the format badge
(SID/SNDH/MOD...) as the notification picture. The seek bar comes from
0.12.0.

**Test on Windows:** keyboard media keys with ChipDeck in the background
and minimised; the overlay that appears on volume change shows the tune;
a Bluetooth headset's buttons.
**Test on Android:** start another music app (ChipDeck pauses); a
notification sound (volume dips); headset buttons; lock screen controls.

## 0.13.0 (part 3): More module formats, and a Future Composer check

**Needs:** nothing. libxmp is already bundled.

**App:** add the formats libxmp already plays to the picker, library and
format filter: **S3M** (Scream Tracker 3), **IT** (Impulse Tracker),
**MED/OctaMED**, **OKT**, **669**, **MTM**, **STM**, **FAR**, **ULT** and the
other libxmp formats, grouped by system (Amiga or PC) in the filter. Each
new format is one line in `formatGroups` plus its badge. Check that IT
tunes with many channels still scope well (`CD_MAX_CHANNELS` is 32; IT can
have 64, so either raise it or show the first 32). Add more Future
Composer names (`.fc13`, `.fc14`, `.smod`) and check them.

**Test on Windows:** play S3M, IT, MED, OKT tunes (Modland has all of
them); a 64-channel IT; refresh the library and use the new filters;
Future Composer 1.3 and 1.4 tunes.
**Test on Android:** a few of the same files, and the filter on the small
screen.

## 0.14.0: HVSC download and update in the app

**Needs:** nothing, but it is the base for 0.15.0 and 0.16.0.

**App:** a new "Get music" page (from the library's menu). For HVSC: shows
the installed HVSC version (from `DOCUMENTS/` in the library location) and
the latest one online; "Download HVSC" downloads and unpacks it into a
folder the user picks and adds it as a library location (with
Songlengths.md5 and STIL picked up automatically); "Update" applies the
official update packs one after the other. A download can be paused,
resumed after a restart, and cancelled. It checks free space first and
shows progress. A weekly check (on startup, at most once a week, can be
switched off) shows a dot on the menu when an update is out.

**Shared downloads code** (used by 0.15.0 and 0.16.0): resumable HTTPS
download to a temporary file, unzip with the `archive` package, then move
into place, so a cancelled or failed download never leaves a broken
folder. Android needs the INTERNET permission added.

**To check first:** the HVSC download hosts are blocked from the cloud dev
container, so the exact URLs, whether HVSC is offered as zip or only 7z,
and the format of the update packs are checked on the test PC before
coding. If only 7z, add the LZMA SDK (public domain) to the core.

**Test on Windows:** download HVSC into an empty folder; play a tune;
pause and resume the download; cancel it (nothing half-unpacked is left);
update an older HVSC copy; the update dot.
**Test on Android:** download to phone storage or SD card over Wi-Fi; turn
the screen off during the download.

## 0.15.0: SNDH archive download and update

**Needs:** 0.14.0.

**App:** "Get music" gets the SNDH archive: download the whole archive,
check for a newer one, update by downloading again and replacing only
changed files (compare size and date, keeping playlists and favourites
valid because paths don't change). Added as a library location.

**To check first:** the archive's current download file and how to tell
its version (on the test PC).

**Test on Windows:** download, play an SNDH, update; playlists with SNDH
tunes still work after the update.
**Test on Android:** download and play.

## 0.16.0: Modland browsing and downloads

**Needs:** 0.14.0.

Modland is far too big to download whole, so it is browsed online instead.

**App:** "Get music" > Modland: browse folders (format > composer > tune),
and search using Modland's own file list (`allmods` index, downloaded once
and refreshed weekly). Download a tune, a composer's folder, or a whole
format folder into a Modland library location, keeping Modland's folder
layout. Only formats ChipDeck plays are shown, and TFMX pairs (mdat. +
smpl.) are downloaded together. Tap a tune to download and play it
straight away ("Play" also keeps it).

**To check first:** the HTTPS mirror's folder listing and the index file
on the test PC.

**Test on Windows:** browse to a composer, play a MOD without saving it
first, download a folder, search for a tune; a TFMX pair plays.
**Test on Android:** browse and play on mobile data and Wi-Fi.

## 0.17.0: Sound options

**Needs:** nothing.

**SID:** the 6581/8580 choice exists. Add the reSIDfp filter settings:
"6581 filter" (dark ... bright, `setFilter6581Curve`) and "8580 filter"
(`setFilter8580Curve`), plus "Digi boost" for 8580 (so `$D418` digis are
heard on an 8580). Changes apply to the playing tune.

**Amiga:** "Stereo separation" 0-100 % for MOD and Amiga TFMX/FC (Amiga
channels are hard left/right; 100 % is the real Amiga, about 30-50 % is
nicer on headphones). libxmp has `XMP_PLAYER_MIX`; for TFMX the core mixes
the left and right channels itself.

**Gap between tunes:** off (default), 1, 2 or 5 s of silence before the
next tune. Optional fade-out over the last 5 s of a tune with a known
length (most SIDs just stop).

**Test on Windows:** switch 6581/8580 and the filter on a filter-heavy SID
(e.g. a Rob Hubbard or Martin Galway tune); a digi tune on 8580 with digi
boost on and off; MOD stereo separation at 0, 50 and 100 % on headphones;
the gap and fade between tunes.
**Test on Android:** the same settings, then restart (they are remembered).

## 0.18.0: Crossfade between tunes

**Needs:** 0.17.0 (shares the gap/fade setting).

**Core:** `cd_audio` gets a second player so the next tune can start while
the current one fades out; both are mixed in the audio callback. Crossfade
length: off, 2, 5 or 8 s. Only when the length of the current tune is
known (otherwise it falls back to the gap). Scopes follow the incoming
tune. Memory and CPU are checked on the test handheld (two SID engines at
once).

**Test on Windows:** play a list with crossfade on (SID to SNDH to MOD);
skip during a crossfade; pause during a crossfade; random order.
**Test on Android:** the same, with the screen off for a few tunes;
check the battery use doesn't jump.

## 0.19.0: Export to WAV and FLAC

**Needs:** 0.12.0 (mutes) and 0.17.0 (sound options), so the export sounds
like the player.

**Core:** `cd_export(path, format, subtune, length_ms, fade_ms, ...)` that
renders with its own `cd_player` (not the playing one) as fast as it can,
writing 16-bit 48 kHz WAV, or FLAC through libFLAC. The CLI gets `--flac`
next to its existing WAV export.

**App:** "Export..." on Now playing, library rows and playlists (whole
list too). Options: format, length (tune length, or a set time), fade-out,
which subtunes, keep mutes. Runs in the background with progress and
cancel; several exports queue up. Windows asks where to save; Android
saves to `Music/ChipDeck` (shared storage) and says where.

**Test on Windows:** export a SID with a Songlengths entry as WAV and FLAC;
play the files in another player (lengths, fade, no clicks); export with a
muted voice; export a whole playlist.
**Test on Android:** export a tune and open it in another app; set it as a
ringtone.

## 0.20.0: AHX and HivelyTracker

**Needs:** nothing.

**Core:** vendor the HivelyTracker replayer (BSD-3-Clause), new backend
`hvl_backend.cpp` for `.ahx` and `.hvl`: subtunes, length (by playing it
through once, like libxmp), per-channel scopes (4 for AHX, up to 16 for
HVL; a small "ChipDeck patch" like the other engines), mute (0.12.0),
seeking (0.12.0). Our own small test tune made by a script in `tools/`.
**App:** formats in the Amiga group, AHX/HVL badges.

**Test on Windows:** AHX and HVL tunes from Modland, scopes, mute, seek,
subtunes.
**Test on Android:** a few of the same.

## 0.21.0: SAP (Atari 8-bit)

**Needs:** nothing.

**Core:** vendor ASAP (GPL-2.0-or-later), new backend for `.sap` (and the
other formats ASAP plays: `.cmc`, `.cm3`, `.cmr`, `.cms`, `.dmc`, `.dlt`,
`.mpt`, `.mpd`, `.rmt`, `.tmc`, `.tm8`, `.tm2`, `.fc`). Subtunes and
lengths come from the SAP header (`TIME` tags). Per-channel scopes for the
4 POKEY channels (8 for stereo tunes), mute and seek. New
`cd_system` value "Atari 8-bit" and a new filter group. ASAP's `.fc` is a
different format from Future Composer, so the core must check the file
before choosing an engine. Our own test tune made by a script.

**Test on Windows:** tunes from the ASMA archive (stereo and mono), scopes,
mute, seek, subtunes; the new filter group.
**Test on Android:** a few of the same.

## Later, not planned yet

- ASMA (Atari 8-bit archive) in "Get music", once SAP plays (reuses
  0.14.0).
- Writable mute toggles on the Android second screen.
- Smart lists by format or composer (reusing the 0.13.0 smart lists).
