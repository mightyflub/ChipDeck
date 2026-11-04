/*
 * ChipDeck core: TFMX-ST, the Atari ST version of Chris Huelsbeck's TFMX
 * (music by Huelsbeck and Rudolf Stember, 1991-92). Same mdat./smpl. file
 * pair as Amiga TFMX, but the instrument macros drive the ST's YM2149
 * sound chip. Played by our own C++ port of the TFMX-ST replay routine
 * (see tfmxst_backend.cpp) feeding AtariAudio's YM2149 emulation.
 * Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
 *
 * Internal to chipdeck-core; not part of the public C API.
 */
#ifndef CHIPDECK_TFMXST_BACKEND_H
#define CHIPDECK_TFMXST_BACKEND_H

#include "chipdeck/chipdeck.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace chipdeck {

class TfmxStTune
{
public:
    // `data` is the mdat file, `smpl` the samples file (digi drums; may be
    // empty, then they stay silent). `name` is shown as the title (file
    // name without the mdat. prefix). subtune is 1-based, 0 = first.
    static std::unique_ptr<TfmxStTune> load(const uint8_t* data, size_t size,
                                            const uint8_t* smpl, size_t smplSize,
                                            const std::string& name, uint32_t sampleRate,
                                            int subtune, std::string& error);
    ~TfmxStTune();

    int subtunes() const { return static_cast<int>(songs_.size()); }
    bool select(int subtune);
    void fillInfo(cd_info* out) const;
    size_t render(int16_t* out, size_t frames, int16_t* chans = nullptr);
    int channelCount() const { return 3; }
    const char* channelName(int ch) const;
    uint32_t positionMs() const;

    struct Replay;  // the ported replay routine (tfmxst_backend.cpp)

private:
    TfmxStTune() = default;
    bool start(int subtune);

    std::vector<uint8_t> pristine_;  // mdat as loaded (macros can modify the copy)
    std::vector<uint8_t> smpl_;
    std::string name_;
    std::vector<int> songs_;         // song numbers (0..31) in the file
    std::vector<int32_t> lengths_;   // ms per song, -1 if it never ends
    int current_ = 1;
    uint32_t rate_ = 0;
    uint64_t framesPlayed_ = 0;
    uint64_t tickAcc_ = 0;           // 50 Hz tick clock, in sample-rate units
    std::unique_ptr<Replay> r_;
};

} // namespace chipdeck

#endif
