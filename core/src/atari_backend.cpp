/*
 * ChipDeck core: Atari ST .sndh and .ym playback via AtariAudio.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "atari_backend.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "AtariAudio.h"

namespace chipdeck {

namespace {

void copyStr(char* dst, size_t cap, const char* src)
{
    std::snprintf(dst, cap, "%s", src ? src : "");
}

int32_t durationMs(const AtariAudioRenderer& r, int subtune)
{
    const uint32_t samples = r.GetSubsongDurationSample(subtune);
    const uint32_t rate = r.GetSongInfo().hostReplayRate;
    if (samples == 0 || rate == 0) return -1;
    return static_cast<int32_t>(uint64_t(samples) * 1000u / rate);
}

void fill(const AtariAudioRenderer& r, int current, cd_info* out)
{
    const AtariAudioRenderer::SongInfo& si = r.GetSongInfo();
    std::memset(out, 0, sizeof *out);
    copyStr(out->title,    sizeof out->title,    si.musicName);
    copyStr(out->author,   sizeof out->author,   si.musicAuthor);
    copyStr(out->released, sizeof out->released, si.year);
    copyStr(out->format,   sizeof out->format,   si.fileFormat);
    out->subtunes = si.subsongCount > 0 ? si.subsongCount : 1;
    out->start_subtune = si.defaultSubsong > 0 ? si.defaultSubsong : 1;
    out->current_subtune = current;
    // SID-only fields stay 0 (sid_chips == 0 means "not a SID tune").
    out->length_ms = durationMs(r, current);
}

} // namespace

bool isAtariTune(const uint8_t* d, size_t n)
{
    // Same checks as AtariAudioRenderer::QuickFileTypeCheck.
    if (!d || n <= 16) return false;
    if (std::memcmp(d, "ICE!", 4) == 0) return true;                       // ICE packed SNDH
    if (d[0] && std::memcmp(d + 2, "-lh5-", 5) == 0) return true;          // LZH packed YM
    if (d[0] == 0x60 && std::memcmp(d + 12, "SNDH", 4) == 0) return true;  // SNDH
    if (std::memcmp(d + 4, "LeOnArD!", 8) == 0) return true;               // YM4/5/6
    static const char* const kYm[] = { "YM2!", "YM3!", "YM3b", "MIX1", "YMT1", "YMT2" };
    for (const char* m : kYm)
        if (std::memcmp(d, m, 4) == 0) return true;
    return false;
}

std::unique_ptr<AtariTune> AtariTune::load(const uint8_t* data, size_t size,
                                           uint32_t sampleRate, int subtune,
                                           std::string& error)
{
    if (size > 0xFFFFFFFFu) { error = "file too large"; return nullptr; }
    std::unique_ptr<AtariTune> t(new AtariTune());
    t->rate_ = sampleRate;
    t->renderer_ = AtariAudioRenderer::Create(data, static_cast<uint32_t>(size), sampleRate);
    if (!t->renderer_) { error = "not a valid SNDH or YM file"; return nullptr; }
    if (subtune <= 0) subtune = t->renderer_->GetSongInfo().defaultSubsong;
    if (subtune <= 0) subtune = 1;
    if (!t->select(subtune)) { error = "cannot start subtune"; return nullptr; }
    return t;
}

bool AtariTune::probe(const uint8_t* data, size_t size, cd_info* out)
{
    if (!isAtariTune(data, size) || size > 0xFFFFFFFFu) return false;
    // Create() only unpacks and parses the header; no emulation runs.
    AtariAudioRenderer* r = AtariAudioRenderer::Create(data, static_cast<uint32_t>(size), 48000);
    if (!r) return false;
    const int def = r->GetSongInfo().defaultSubsong > 0 ? r->GetSongInfo().defaultSubsong : 1;
    fill(*r, def, out);
    AtariAudioRenderer::Destroy(r);
    return true;
}

AtariTune::~AtariTune()
{
    if (renderer_) AtariAudioRenderer::Destroy(renderer_);
}

int AtariTune::subtunes() const
{
    const int n = renderer_->GetSongInfo().subsongCount;
    return n > 0 ? n : 1;
}

bool AtariTune::select(int subtune)
{
    if (subtune < 1 || subtune > subtunes()) return false;
    if (!renderer_->InitSubSong(subtune)) return false;
    current_ = subtune;
    framesPlayed_ = 0;
    return true;
}

void AtariTune::fillInfo(cd_info* out) const
{
    fill(*renderer_, current_, out);
}

size_t AtariTune::render(int16_t* out, size_t frames)
{
    const size_t kChunk = 4096;
    mono_.resize(kChunk);
    size_t done = 0;
    while (done < frames)
    {
        const size_t n = std::min(kChunk, frames - done);
        // If the emulated 68000 player crashes, AtariAudio stops writing,
        // so clear first and the result is silence instead of garbage.
        std::fill(mono_.begin(), mono_.begin() + n, int16_t(0));
        renderer_->AudioRender(mono_.data(), static_cast<uint32_t>(n));
        int16_t* o = out + done * 2;
        for (size_t i = 0; i < n; ++i)
            o[i * 2] = o[i * 2 + 1] = mono_[i];
        done += n;
    }
    framesPlayed_ += frames;
    return frames;
}

uint32_t AtariTune::positionMs() const
{
    return rate_ ? static_cast<uint32_t>(framesPlayed_ * 1000u / rate_) : 0;
}

} // namespace chipdeck
