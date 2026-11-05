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
    out->system = CD_SYSTEM_ATARI_ST;
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
    // AtariAudio's visual info has one signed byte per channel per sample:
    // YM A, B, C, then the STE DAC (or the sample channel of MIX1/YMT).
    const AtariAudioRenderer::SongInfo& si = t->renderer_->GetSongInfo();
    const char* fmt = si.fileFormat ? si.fileFormat : "";
    if (si.fileType == AtariAudioRenderer::eFileType::eSndh)
        t->chanBytes_ = { 0, 1, 2, 3 };
    else if (std::strncmp(fmt, "YM ", 3) == 0)
        t->chanBytes_ = { 0, 1, 2 };
    else
        t->chanBytes_ = { 3 };
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
    setMute(mute_);  // InitSubSong unmutes everything
    return true;
}

void AtariTune::setMute(uint32_t mask)
{
    mute_ = mask;
    // AtariAudio's mask: bit 0-2 YM A-C, bit 3 STE DAC / sample channel.
    uint32_t m = 0;
    for (size_t k = 0; k < chanBytes_.size(); ++k)
        if (mask & (1u << k)) m |= 1u << chanBytes_[k];
    renderer_->MuteVoices(m);
}

void AtariTune::seek(uint32_t ms)
{
    const uint64_t target = uint64_t(ms) * rate_ / 1000u;
    if (target < framesPlayed_) select(current_);
    // No seek in AtariAudio: run the emulation without keeping the sound
    // (about 80x real time).
    while (framesPlayed_ < target)
    {
        const uint32_t n = static_cast<uint32_t>(std::min<uint64_t>(target - framesPlayed_, 1u << 16));
        renderer_->FastForward(n);
        framesPlayed_ += n;
    }
}

void AtariTune::fillInfo(cd_info* out) const
{
    fill(*renderer_, current_, out);
}

const char* AtariTune::channelName(int ch) const
{
    if (ch < 0 || ch >= channelCount()) return "";
    static const char* const kNames[] = { "A", "B", "C", "DAC" };
    if (chanBytes_.size() == 1) return "Samples";
    return kNames[chanBytes_[static_cast<size_t>(ch)]];
}

size_t AtariTune::render(int16_t* out, size_t frames, int16_t* chans)
{
    const size_t kChunk = 4096;
    mono_.resize(kChunk);
    if (chans) visual_.resize(kChunk);
    size_t done = 0;
    while (done < frames)
    {
        const size_t n = std::min(kChunk, frames - done);
        // If the emulated 68000 player crashes, AtariAudio stops writing,
        // so clear first and the result is silence instead of garbage.
        std::fill(mono_.begin(), mono_.begin() + n, int16_t(0));
        if (chans)
        {
            std::fill(visual_.begin(), visual_.begin() + n, 0u);
            renderer_->AudioRenderWithVisualInfos(mono_.data(), static_cast<uint32_t>(n),
                                                  visual_.data());
            const size_t nc = chanBytes_.size();
            int16_t* c = chans + done * nc;
            for (size_t i = 0; i < n; ++i)
                for (size_t k = 0; k < nc; ++k)
                {
                    const int8_t v = static_cast<int8_t>(visual_[i] >> (chanBytes_[k] * 8));
                    c[i * nc + k] = static_cast<int16_t>(v * 256);
                }
        }
        else
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
