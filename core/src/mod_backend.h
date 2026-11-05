/*
 * ChipDeck core: Amiga .mod and Fasttracker 2 .xm playback via libxmp.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * Internal to chipdeck-core; not part of the public C API.
 */
#ifndef CHIPDECK_MOD_BACKEND_H
#define CHIPDECK_MOD_BACKEND_H

#include "chipdeck/chipdeck.h"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

namespace chipdeck {

class ModTune
{
public:
    // Load a module from an open file (libxmp unpacks PowerPacker, zip, gz,
    // lha etc. on the way) or from memory (no unpacking), and start
    // `subtune` (1-based, 0 = first). Returns nullptr and sets `error` if
    // the data is not a module libxmp knows.
    static std::unique_ptr<ModTune> loadFile(FILE* f, long size, uint32_t sampleRate,
                                             int subtune, std::string& error);
    static std::unique_ptr<ModTune> loadMemory(const uint8_t* data, size_t size,
                                               uint32_t sampleRate, int subtune,
                                               std::string& error);
    // Read metadata only (for cd_probe_file).
    static bool probeFile(FILE* f, long size, cd_info* out);
    ~ModTune();

    int subtunes() const;
    // Restart at a 1-based subtune (libxmp "sequence"). False if out of range.
    bool select(int subtune);
    void fillInfo(cd_info* out) const;
    // Interleaved stereo output. If chans is not null it also gets
    // channelCount() values per frame, one per tracker channel.
    size_t render(int16_t* out, size_t frames, int16_t* chans = nullptr);
    int channelCount() const { return channels_; }
    const char* channelName(int ch) const;
    uint32_t positionMs() const;
    // Mute channels: bit n mutes channel n (as numbered for the scopes).
    // Kept when the subtune changes.
    void setMute(uint32_t mask);
    // Jump to `ms` from the start of the current subtune.
    void seek(uint32_t ms);

private:
    ModTune() = default;
    bool start(uint32_t sampleRate, int subtune, std::string& error);
    void* ctx_ = nullptr;   // xmp_context
    uint32_t rate_ = 0;
    int current_ = 1;
    int channels_ = 0;
    uint64_t framesPlayed_ = 0;
    uint32_t mute_ = 0;
    // One libxmp tick of output not yet handed out.
    std::vector<int16_t> tick_;      // interleaved stereo
    std::vector<int16_t> tickChans_; // channels_ values per frame
    size_t tickPos_ = 0;             // next unread frame in tick_
    std::vector<std::string> names_;
};

} // namespace chipdeck

#endif
