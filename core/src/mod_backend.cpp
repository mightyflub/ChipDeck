/*
 * ChipDeck core: Amiga .mod and Fasttracker 2 .xm playback via libxmp.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 */
#include "mod_backend.h"

#include <algorithm>
#include <cstring>

#include "xmp.h"

namespace chipdeck {

namespace {

void copyStr(char* dst, size_t cap, const char* src)
{
    std::snprintf(dst, cap, "%s", src ? src : "");
}

// Trim trailing spaces (module names are often space padded).
std::string trimmed(const char* s)
{
    std::string r = s ? s : "";
    while (!r.empty() && (r.back() == ' ' || r.back() == '\0')) r.pop_back();
    size_t i = 0;
    while (i < r.size() && r[i] == ' ') ++i;
    return r.substr(i);
}

void fill(xmp_context ctx, int current, cd_info* out)
{
    xmp_module_info mi;
    xmp_get_module_info(ctx, &mi);
    std::memset(out, 0, sizeof *out);
    out->length_ms = -1;
    out->system = CD_SYSTEM_AMIGA;
    if (!mi.mod) return;
    // libxmp names XM files "<tracker> XM <version>", e.g.
    // "FastTracker v2.00 XM 1.04"; everything else is an Amiga format here.
    if (std::strstr(mi.mod->type, " XM ")) out->system = CD_SYSTEM_PC;
    copyStr(out->title,  sizeof out->title,  trimmed(mi.mod->name).c_str());
    copyStr(out->format, sizeof out->format, trimmed(mi.mod->type).c_str());
    out->subtunes = mi.num_sequences > 0 ? mi.num_sequences : 1;
    out->start_subtune = 1;
    out->current_subtune = current;
    // SID-only fields stay 0 (sid_chips == 0 means "not a SID tune").
    if (mi.seq_data && current >= 1 && current <= mi.num_sequences)
    {
        const int ms = mi.seq_data[current - 1].duration;
        out->length_ms = ms > 0 ? ms : -1;
    }
}

} // namespace

std::unique_ptr<ModTune> ModTune::loadFile(FILE* f, long size, uint32_t sampleRate,
                                           int subtune, std::string& error)
{
    std::unique_ptr<ModTune> t(new ModTune());
    t->ctx_ = xmp_create_context();
    if (!t->ctx_) { error = "out of memory"; return nullptr; }
    if (xmp_load_module_from_file(static_cast<xmp_context>(t->ctx_), f, size) != 0)
    {
        error = "not a module ChipDeck can play";
        return nullptr;
    }
    if (!t->start(sampleRate, subtune, error)) return nullptr;
    return t;
}

std::unique_ptr<ModTune> ModTune::loadMemory(const uint8_t* data, size_t size,
                                             uint32_t sampleRate, int subtune,
                                             std::string& error)
{
    if (size > 0x7FFFFFFF) { error = "file too large"; return nullptr; }
    std::unique_ptr<ModTune> t(new ModTune());
    t->ctx_ = xmp_create_context();
    if (!t->ctx_) { error = "out of memory"; return nullptr; }
    if (xmp_load_module_from_memory(static_cast<xmp_context>(t->ctx_), data,
                                    static_cast<long>(size)) != 0)
    {
        error = "not a module ChipDeck can play";
        return nullptr;
    }
    if (!t->start(sampleRate, subtune, error)) return nullptr;
    return t;
}

bool ModTune::start(uint32_t sampleRate, int subtune, std::string& error)
{
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    rate_ = sampleRate;
    xmp_module_info mi;
    xmp_get_module_info(ctx, &mi);
    channels_ = mi.mod ? std::min(mi.mod->chn, CD_MAX_CHANNELS) : 0;
    names_.clear();
    for (int c = 0; c < channels_; ++c)
        names_.push_back(std::to_string(c + 1));
    // Paula (Amiga 500) mixer for Amiga modules: BLEP-synthesised output and
    // the LED filter, as on the real machine. Other formats use the normal
    // mixer with cubic spline interpolation.
    xmp_set_player(ctx, XMP_PLAYER_FLAGS, XMP_FLAGS_A500);
    xmp_chipdeck_set_tap(ctx, channels_);
    if (subtune <= 0) subtune = 1;
    if (!select(subtune)) { error = "cannot start the module"; return false; }
    return true;
}

bool ModTune::probeFile(FILE* f, long size, cd_info* out)
{
    xmp_context ctx = xmp_create_context();
    if (!ctx) return false;
    // Loading also scans the song for its sequences and their durations;
    // no audio is rendered.
    bool ok = xmp_load_module_from_file(ctx, f, size) == 0;
    if (ok)
    {
        fill(ctx, 1, out);
        xmp_release_module(ctx);
    }
    xmp_free_context(ctx);
    return ok;
}

ModTune::~ModTune()
{
    if (!ctx_) return;
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    if (xmp_get_player(ctx, XMP_PLAYER_STATE) >= XMP_STATE_PLAYING) xmp_end_player(ctx);
    if (xmp_get_player(ctx, XMP_PLAYER_STATE) >= XMP_STATE_LOADED) xmp_release_module(ctx);
    xmp_free_context(ctx);
}

int ModTune::subtunes() const
{
    xmp_module_info mi;
    xmp_get_module_info(static_cast<xmp_context>(ctx_), &mi);
    return mi.num_sequences > 0 ? mi.num_sequences : 1;
}

bool ModTune::select(int subtune)
{
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    if (subtune < 1 || subtune > subtunes()) return false;
    if (xmp_get_player(ctx, XMP_PLAYER_STATE) >= XMP_STATE_PLAYING) xmp_end_player(ctx);
    if (xmp_start_player(ctx, static_cast<int>(rate_), 0) != 0) return false;
    xmp_set_player(ctx, XMP_PLAYER_INTERP, XMP_INTERP_SPLINE);
    if (subtune > 1)
    {
        xmp_module_info mi;
        xmp_get_module_info(ctx, &mi);
        xmp_set_position(ctx, mi.seq_data[subtune - 1].entry_point);
    }
    current_ = subtune;
    framesPlayed_ = 0;
    tick_.clear();
    tickChans_.clear();
    tickPos_ = 0;
    setMute(mute_);
    return true;
}

void ModTune::setMute(uint32_t mask)
{
    mute_ = mask;
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    for (int c = 0; c < channels_; ++c)
        xmp_channel_mute(ctx, c, (mask >> c) & 1u);
}

void ModTune::seek(uint32_t ms)
{
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    const uint64_t target = uint64_t(ms) * rate_ / 1000u;
    if (target < framesPlayed_) select(current_);
    if (target <= framesPlayed_) return;
    // Jump to the start of the pattern playing at `ms` (times are counted
    // from the start of the current sequence), unless that is behind us.
    const uint64_t now = framesPlayed_;
    tick_.clear();
    tickChans_.clear();
    tickPos_ = 0;
    xmp_seek_time(ctx, static_cast<int>(ms));
    if (xmp_play_frame(ctx) == 0)
    {
        xmp_frame_info fi;
        xmp_get_frame_info(ctx, &fi);
        // fi.time is the end of the frame just made; its start is where
        // the pattern starts.
        const double startMs = fi.time - fi.frame_time / 1000.0;
        const uint64_t at = startMs > 0 ? static_cast<uint64_t>(startMs * rate_ / 1000.0) : 0;
        if (at >= now && at <= target)
        {
            const size_t n = static_cast<size_t>(std::max(0, fi.buffer_size)) / 4;
            const int16_t* b = static_cast<const int16_t*>(fi.buffer);
            tick_.assign(b, b + n * 2);
            tickChans_.assign(n * static_cast<size_t>(channels_), 0);
            if (channels_ > 0)
                xmp_chipdeck_read_tap(ctx, tickChans_.data(), static_cast<int>(n));
            framesPlayed_ = at;
        }
        else
        {
            // Song loops or jumps backwards: play forward from where we were.
            select(current_);
        }
    }
    // Play the rest (less than one pattern, or all of it after a fallback).
    std::vector<int16_t> scratch(4096 * 2);
    while (framesPlayed_ < target)
    {
        const size_t n = static_cast<size_t>(std::min<uint64_t>(target - framesPlayed_, 4096));
        render(scratch.data(), n, nullptr);
    }
}

void ModTune::fillInfo(cd_info* out) const
{
    fill(static_cast<xmp_context>(ctx_), current_, out);
}

const char* ModTune::channelName(int ch) const
{
    if (ch < 0 || ch >= channels_) return "";
    return names_[static_cast<size_t>(ch)].c_str();
}

size_t ModTune::render(int16_t* out, size_t frames, int16_t* chans)
{
    xmp_context ctx = static_cast<xmp_context>(ctx_);
    const size_t nc = static_cast<size_t>(channels_);
    size_t done = 0;
    int stalls = 0;
    while (done < frames)
    {
        const size_t have = tick_.size() / 2 - tickPos_;
        if (have == 0)
        {
            // Render the next tick (one row step of the tracker, ~20 ms).
            tickPos_ = 0;
            tick_.clear();
            if (xmp_play_frame(ctx) == 0)
            {
                xmp_frame_info fi;
                xmp_get_frame_info(ctx, &fi);
                const size_t n = static_cast<size_t>(std::max(0, fi.buffer_size)) / 4;
                const int16_t* b = static_cast<const int16_t*>(fi.buffer);
                tick_.assign(b, b + n * 2);
                tickChans_.assign(n * nc, 0);
                if (nc > 0)
                    xmp_chipdeck_read_tap(ctx, tickChans_.data(), static_cast<int>(n));
            }
            if (tick_.empty())
            {
                // Module stopped (or a broken tick): play silence.
                if (++stalls > 4)
                {
                    const size_t rest = frames - done;
                    std::memset(out + done * 2, 0, rest * 2 * sizeof(int16_t));
                    if (chans) std::memset(chans + done * nc, 0, rest * nc * sizeof(int16_t));
                    done = frames;
                }
                continue;
            }
            continue;
        }
        const size_t take = std::min(have, frames - done);
        std::memcpy(out + done * 2, tick_.data() + tickPos_ * 2, take * 2 * sizeof(int16_t));
        if (chans && nc > 0)
            std::memcpy(chans + done * nc, tickChans_.data() + tickPos_ * nc,
                        take * nc * sizeof(int16_t));
        tickPos_ += take;
        done += take;
    }
    framesPlayed_ += frames;
    return frames;
}

uint32_t ModTune::positionMs() const
{
    return rate_ ? static_cast<uint32_t>(framesPlayed_ * 1000u / rate_) : 0;
}

} // namespace chipdeck
