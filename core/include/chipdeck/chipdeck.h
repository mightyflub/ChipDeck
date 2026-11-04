/*
 * ChipDeck core: a small C API over the chiptune emulation engines.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * The same API is meant to be called from the CLI (C++), from Flutter via
 * dart:ffi, and from Android via JNI, so it is plain C with no C++ types.
 *
 * Audio is always 16-bit signed, interleaved stereo, at the sample rate
 * given to cd_create(). All strings are UTF-8.
 *
 * Threading: every function on one cd_player is internally locked, so it is
 * safe to call cd_render() from an audio thread while the UI thread calls
 * cd_select_subtune() or cd_get_info().
 */
#ifndef CHIPDECK_H
#define CHIPDECK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(CHIPDECK_SHARED)
#  ifdef CHIPDECK_BUILDING
#    define CD_API __declspec(dllexport)
#  else
#    define CD_API __declspec(dllimport)
#  endif
#elif defined(__GNUC__) || defined(__clang__)
#  define CD_API __attribute__((visibility("default")))
#else
#  define CD_API
#endif

typedef struct cd_player cd_player;

typedef enum cd_sid_model {
    CD_SID_AUTO = 0, /* use what the tune asks for (default) */
    CD_SID_6581 = 1,
    CD_SID_8580 = 2
} cd_sid_model;

typedef struct cd_info {
    char title[64];
    char author[64];
    char released[64];
    char format[64];      /* e.g. "PlaySID one-file format (PSID)" */
    int subtunes;         /* number of subtunes, >= 1 */
    int start_subtune;    /* 1-based default subtune */
    int current_subtune;  /* 1-based */
    int sid_chips;        /* 1, 2 or 3 */
    int sid_model;        /* cd_sid_model actually in use for chip 1 */
    int is_ntsc;          /* 1 if the tune runs at NTSC speed */
    int32_t length_ms;    /* from Songlengths database, or -1 if unknown */
} cd_info;

/* Library version string, e.g. "0.1.0 (libsidplayfp 3.1.2)". */
CD_API const char* cd_version(void);

/* Create a player that renders at sample_rate Hz (e.g. 44100 or 48000). */
CD_API cd_player* cd_create(uint32_t sample_rate);
CD_API void cd_destroy(cd_player* p);

/* Last error message for this player, or "" if none. Valid until next call. */
CD_API const char* cd_last_error(cd_player* p);

/* Optional: HVSC Songlengths.md5 file so cd_info.length_ms is filled in. */
CD_API int cd_load_songlengths(cd_player* p, const char* path);

/* Optional: C64 ROM images (8 KB each). Improves RSID compatibility.
 * Any path may be NULL. Must be called before cd_load_*(). */
CD_API int cd_set_roms(cd_player* p, const char* kernal, const char* basic,
                       const char* chargen);

/* Force a SID model (default CD_SID_AUTO). Takes effect on next load. */
CD_API void cd_set_sid_model(cd_player* p, cd_sid_model model);

/* Load a tune. subtune is 1-based; 0 means the tune's default.
 * Returns 0 on success, non-zero on error (see cd_last_error). */
CD_API int cd_load_file(cd_player* p, const char* path, int subtune);
CD_API int cd_load_memory(cd_player* p, const void* data, size_t size,
                          int subtune);

/* Switch subtune (1-based) and restart playback from the beginning. */
CD_API int cd_select_subtune(cd_player* p, int subtune);

CD_API int cd_get_info(cd_player* p, cd_info* out);

/* Render up to `frames` stereo frames (2 * frames int16 values) into out.
 * Returns frames written; less than requested only on error (0 if no tune). */
CD_API size_t cd_render(cd_player* p, int16_t* out, size_t frames);

/* Playback position in milliseconds since the current subtune started. */
CD_API uint32_t cd_position_ms(cd_player* p);

/* Copy the 32 registers of SID chip `chip` (0-based), for visualisers.
 * Returns 0 on success. Register layout is the C64 SID ($D400-$D41F). */
CD_API int cd_get_sid_registers(cd_player* p, int chip, uint8_t regs[32]);

/* ---------------------------------------------------------------------
 * Per-channel output, for visualisers (one oscilloscope per channel).
 * SID: per chip "V1", "V2", "V3" (each voice before filter and volume)
 * and "Digi" (the $D418 master volume, which volume-register digis and
 * drums play through); with 2 or 3 chips the names get a "2:"/"3:" prefix.
 * SNDH: "A", "B", "C" (YM2149) and "DAC" (STE DMA sound). YM: "A", "B",
 * "C". The data follows cd_render(), so it matches what is being heard.
 * Values are DC-blocked so silent channels sit at 0.
 * --------------------------------------------------------------------- */
#define CD_MAX_CHANNELS 12

/* Number of channels of the loaded tune (0 if none). */
CD_API int cd_channel_count(cd_player* p);

/* Copy channel `ch`'s name (UTF-8, NUL-terminated) into out. 0 on success. */
CD_API int cd_channel_name(cd_player* p, int ch, char* out, size_t cap);

/* Copy the most recent `frames` samples of every channel, channel after
 * channel (out[ch * frames + i], newest last). out must hold
 * cd_channel_count() * frames values; frames is capped at 4096.
 * Returns frames copied per channel. */
CD_API size_t cd_channel_scope(cd_player* p, int16_t* out, size_t frames);

/* Read a tune's metadata without creating a player (fast, for file lists).
 * songlengths_path may be NULL. Returns 0 on success. */
CD_API int cd_probe_file(const char* path, const char* songlengths_path,
                         cd_info* out);

/* ---------------------------------------------------------------------
 * Audio output (optional, built into the chipdeck shared library).
 * Owns a cd_player and plays it on the default audio device with
 * miniaudio (WASAPI on Windows, AAudio/OpenSL on Android, Pulse/ALSA on
 * Linux). UIs that do not have their own audio stack use this.
 * --------------------------------------------------------------------- */
typedef struct cd_audio cd_audio;

/* Open the default output device at 48 kHz stereo. NULL on failure. */
CD_API cd_audio* cd_audio_create(void);
CD_API void cd_audio_destroy(cd_audio* a);
/* The player this output renders from; use the cd_* calls above on it. */
CD_API cd_player* cd_audio_player(cd_audio* a);
CD_API void cd_audio_set_playing(cd_audio* a, int playing);
CD_API int cd_audio_is_playing(cd_audio* a);
/* 0.0 (mute) .. 1.0 (full). */
CD_API void cd_audio_set_volume(cd_audio* a, float volume);
/* Copy the most recent `frames` output samples (mono mix, newest last)
 * for an oscilloscope. Returns frames copied. */
CD_API size_t cd_audio_scope(cd_audio* a, int16_t* out, size_t frames);
CD_API uint32_t cd_audio_sample_rate(cd_audio* a);

#ifdef __cplusplus
}
#endif
#endif /* CHIPDECK_H */
