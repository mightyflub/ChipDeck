/*
 * ChipDeck core: Atari ST .sndh and .ym playback via AtariAudio.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * Internal to chipdeck-core; not part of the public C API.
 */
#ifndef CHIPDECK_ATARI_BACKEND_H
#define CHIPDECK_ATARI_BACKEND_H

#include "chipdeck/chipdeck.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class AtariAudioRenderer;

namespace chipdeck {

// True if the data looks like an Atari ST tune (SNDH, ICE packed SNDH,
// YM of any version, or LZH packed YM). Checks magic bytes only.
bool isAtariTune(const uint8_t* data, size_t size);

class AtariTune
{
public:
    // Parse the tune and start `subtune` (1-based, 0 = default).
    // Returns nullptr and sets `error` on failure.
    static std::unique_ptr<AtariTune> load(const uint8_t* data, size_t size,
                                           uint32_t sampleRate, int subtune,
                                           std::string& error);
    // Parse only, without starting emulation (for cd_probe_file).
    static bool probe(const uint8_t* data, size_t size, cd_info* out);
    ~AtariTune();

    int subtunes() const;
    // Restart at a 1-based subtune. Returns false if out of range.
    bool select(int subtune);
    void fillInfo(cd_info* out) const;
    // Interleaved stereo output (AtariAudio is mono; both channels equal).
    // If chans is not null it also gets channelCount() values per frame,
    // one per chip channel (for per-channel oscilloscopes).
    size_t render(int16_t* out, size_t frames, int16_t* chans = nullptr);
    // Channels shown by visualisers: YM A, B, C (+ STE DAC for SNDH).
    int channelCount() const { return static_cast<int>(chanBytes_.size()); }
    const char* channelName(int ch) const;
    uint32_t positionMs() const;
    // Mute channels: bit n mutes channel n (as numbered for the scopes).
    // Kept when the subtune changes.
    void setMute(uint32_t mask);
    // Jump to `ms` from the start of the current subtune.
    void seek(uint32_t ms);

private:
    AtariTune() = default;
    AtariAudioRenderer* renderer_ = nullptr;
    uint32_t rate_ = 0;
    int current_ = 1;
    uint64_t framesPlayed_ = 0;
    uint32_t mute_ = 0;
    std::vector<int16_t> mono_;
    std::vector<uint32_t> visual_;
    std::vector<int> chanBytes_;  // byte of AtariAudio's visual info per channel
};

} // namespace chipdeck

#endif
