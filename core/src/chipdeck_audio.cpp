/*
 * ChipDeck audio output: plays a cd_player on the default device (miniaudio).
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#define CHIPDECK_BUILDING
#include "chipdeck/chipdeck.h"
#include "miniaudio.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <vector>

namespace {
const uint32_t kRate = 48000;
const size_t kScopeFrames = 4096;  // ring buffer for the oscilloscope
}

struct cd_audio
{
    ma_device device{};
    cd_player* player = nullptr;
    std::atomic<bool> playing{false};
    std::atomic<float> volume{0.8f};

    std::mutex scopeLock;
    std::vector<int16_t> scope = std::vector<int16_t>(kScopeFrames, 0);
    size_t scopePos = 0;  // next write index
};

static void dataCallback(ma_device* dev, void* out, const void*, ma_uint32 frames)
{
    cd_audio* a = static_cast<cd_audio*>(dev->pUserData);
    int16_t* o = static_cast<int16_t*>(out);
    size_t got = 0;
    if (a->playing.load())
        got = cd_render(a->player, o, frames);
    if (got < frames)
        std::memset(o + got * 2, 0, (frames - got) * 2 * sizeof(int16_t));

    const float vol = a->volume.load();
    std::lock_guard<std::mutex> g(a->scopeLock);
    for (ma_uint32 i = 0; i < frames; ++i)
    {
        int l = o[i * 2], r = o[i * 2 + 1];
        a->scope[a->scopePos] = static_cast<int16_t>((l + r) / 2);
        a->scopePos = (a->scopePos + 1) % kScopeFrames;
        o[i * 2]     = static_cast<int16_t>(l * vol);
        o[i * 2 + 1] = static_cast<int16_t>(r * vol);
    }
}

extern "C" {

cd_audio* cd_audio_create(void)
{
    cd_audio* a = new (std::nothrow) cd_audio();
    if (!a) return nullptr;
    a->player = cd_create(kRate);
    if (!a->player) { delete a; return nullptr; }

    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_s16;
    cfg.playback.channels = 2;
    cfg.sampleRate = kRate;
    cfg.dataCallback = dataCallback;
    cfg.pUserData = a;
    if (ma_device_init(nullptr, &cfg, &a->device) != MA_SUCCESS)
    {
        cd_destroy(a->player);
        delete a;
        return nullptr;
    }
    if (ma_device_start(&a->device) != MA_SUCCESS)
    {
        ma_device_uninit(&a->device);
        cd_destroy(a->player);
        delete a;
        return nullptr;
    }
    return a;
}

void cd_audio_destroy(cd_audio* a)
{
    if (!a) return;
    ma_device_uninit(&a->device);
    cd_destroy(a->player);
    delete a;
}

cd_player* cd_audio_player(cd_audio* a) { return a ? a->player : nullptr; }

void cd_audio_set_playing(cd_audio* a, int playing)
{
    if (a) a->playing = playing != 0;
}

int cd_audio_is_playing(cd_audio* a) { return a && a->playing ? 1 : 0; }

void cd_audio_set_volume(cd_audio* a, float volume)
{
    if (!a) return;
    if (volume < 0) volume = 0;
    if (volume > 1) volume = 1;
    a->volume = volume;
}

size_t cd_audio_scope(cd_audio* a, int16_t* out, size_t frames)
{
    if (!a || !out) return 0;
    if (frames > kScopeFrames) frames = kScopeFrames;
    std::lock_guard<std::mutex> g(a->scopeLock);
    size_t start = (a->scopePos + kScopeFrames - frames) % kScopeFrames;
    for (size_t i = 0; i < frames; ++i)
        out[i] = a->scope[(start + i) % kScopeFrames];
    return frames;
}

uint32_t cd_audio_sample_rate(cd_audio* a) { return a ? kRate : 0; }

} // extern "C"
